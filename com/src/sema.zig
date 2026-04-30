const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Scope = struct {
    names: std.ArrayListUnmanaged([]const u8) = .{},

    fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
    }

    fn contains(self: *const Scope, name: []const u8) bool {
        for (self.names.items) |it| {
            if (std.mem.eql(u8, it, name)) return true;
        }
        return false;
    }
};

pub const ErrorSite = struct {
    line: usize,
    col: usize,
};

var last_error_site: ?ErrorSite = null;

pub fn takeLastErrorSite() ?ErrorSite {
    const out = last_error_site;
    last_error_site = null;
    return out;
}

pub fn checkProgram(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    last_error_site = null;
    if (program.source_len == 0) return error.EmptySource;
    if (program.token_count == 0) return error.EmptyTokenStream;
    try checkFuncDeclNaming(tokens);
    if (program.top_level_count == 0) return markErrorAt(tokens, 0, error.NoTopLevelDecl);

    try checkTypeDeclNaming(tokens);
    try checkSingleValuePositions(program, tokens);
    try checkAsyncControlArity(program.func_sigs, tokens);
    try checkIfPatternBind(tokens);
    try checkLoopHeader(tokens);
    try checkAssignmentConstraints(allocator, tokens);
}

fn checkFuncDeclNaming(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        if (!isKeyword(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidFuncDeclName);
    }
}

const DirectCallSite = struct {
    call: parser.FuncCallRef,
    start_tok_idx: usize,
};

fn checkSingleValuePositions(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.condition_exprs) |site| {
        const call_site = findDirectCallAtRoot(program, site.root_expr_idx);
        if (call_site == null) continue;

        const resolved = resolveConditionCallReturnArity(
            program.func_sigs,
            call_site.?.call.func_name,
            call_site.?.call.arg_count,
        );
        switch (resolved) {
            .unknown => continue, // 可能是外部导入函数, 此阶段不阻断
            .single => continue,
            .multi => {
                switch (site.context) {
                    .if_cond => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInIfCondition),
                    .if_bind_rhs => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInIfBindRhs),
                    .match_target => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInMatchTarget),
                }
            },
            .ambiguous => return markErrorAt(tokens, call_site.?.start_tok_idx, error.AmbiguousConditionCallReturnArity),
        }
    }
}

fn findDirectCallAtRoot(program: parser.Program, root_idx: usize) ?DirectCallSite {
    if (root_idx >= program.expr_nodes.len) return null;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .call => .{
            .call = node.data.call,
            .start_tok_idx = node.start_tok,
        },
        .paren => findDirectCallAtRoot(program, node.data.child),
        else => null,
    };
}

const ReturnArityResolve = enum {
    unknown,
    single,
    multi,
    ambiguous,
};

fn resolveConditionCallReturnArity(
    func_sigs: []const parser.FuncSig,
    func_name: []const u8,
    arg_count: usize,
) ReturnArityResolve {
    var seen = false;
    var seen_single = false;
    var seen_multi = false;

    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, func_name)) continue;
        if (!isArgCountCompatible(sig, arg_count)) continue;
        seen = true;
        if (sig.return_arity <= 1) {
            seen_single = true;
        } else {
            seen_multi = true;
        }
    }

    if (!seen) return .unknown;
    if (seen_single and seen_multi) return .ambiguous;
    if (seen_multi) return .multi;
    return .single;
}

fn isArgCountCompatible(sig: parser.FuncSig, arg_count: usize) bool {
    if (arg_count < sig.param_min) return false;
    if (sig.param_max) |max_count| {
        return arg_count <= max_count;
    }
    return true;
}

fn checkAsyncControlArity(func_sigs: []const parser.FuncSig, tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (parseImportDeclEnd(tokens, i)) |next_idx| {
                i = next_idx - 1;
                continue;
            }
        }

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (i + 1 >= tokens.len) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;

        const argc = try parseCallArgCount(tokens, i + 1);
        if (hasUserFuncMatch(func_sigs, t.lexeme, argc)) continue;

        if (tokEq(t, "done")) {
            if (argc == 0) return markErrorAt(tokens, i, error.DoneCallNeedsArg);
            if (argc != 1) return markErrorAt(tokens, i, error.DoneCallArity);
            continue;
        }

        if (tokEq(t, "wait")) {
            if (argc != 1 and argc != 2) return markErrorAt(tokens, i, error.AsyncCtrlArity);
            continue;
        }

        if (tokEq(t, "cancel") or tokEq(t, "status")) {
            if (argc != 1) return markErrorAt(tokens, i, error.AsyncCtrlArity);
            continue;
        }

        if (tokEq(t, "wait_one") or tokEq(t, "wait_any") or tokEq(t, "wait_all")) {
            if (argc < 2) return markErrorAt(tokens, i, error.AsyncCtrlArity);
            continue;
        }
    }
}

fn hasUserFuncMatch(func_sigs: []const parser.FuncSig, name: []const u8, argc: usize) bool {
    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, name)) continue;
        if (!isArgCountCompatible(sig, argc)) continue;
        return true;
    }
    return false;
}

fn parseCallArgCount(tokens: []const lexer.Token, open_paren_idx: usize) !usize {
    var i = open_paren_idx + 1;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var argc: usize = 0;
    var has_arg_token = false;

    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            has_arg_token = true;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren == 0) break;
            depth_paren -= 1;
            has_arg_token = true;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            has_arg_token = true;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace == 0) continue;
            depth_brace -= 1;
            has_arg_token = true;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            has_arg_token = true;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle == 0) continue;
            depth_angle -= 1;
            has_arg_token = true;
            continue;
        }

        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) {
            if (!has_arg_token) return markErrorAt(tokens, i, error.InvalidCallArgList);
            argc += 1;
            has_arg_token = false;
            continue;
        }
        has_arg_token = true;
    }

    if (i >= tokens.len) return markErrorAt(tokens, open_paren_idx, error.UnterminatedCall);
    if (!has_arg_token) return argc; // zero args or trailing comma
    return argc + 1;
}

fn parseImportDeclEnd(tokens: []const lexer.Token, start_idx: usize) ?usize {
    if (!tokEq(tokens[start_idx], "{")) return null;
    const close_brace = findMatching(tokens, start_idx, "{", "}") catch return null;
    if (close_brace + 5 >= tokens.len) return null;

    const colon_idx = close_brace + 1;
    if (!tokEq(tokens[colon_idx], ":")) return null;
    if (!tokEq(tokens[colon_idx + 1], "=")) return null;
    if (!tokEq(tokens[colon_idx + 2], "@")) return null;
    if (!tokEq(tokens[colon_idx + 3], "(")) return null;
    if (tokens[colon_idx + 4].kind != .string) return null;

    const close_paren = findMatching(tokens, colon_idx + 3, "(", ")") catch return null;
    if (close_paren != colon_idx + 5) return null;
    return close_paren + 1;
}

fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    if (open_idx >= tokens.len or !tokEq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], close)) continue;

        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn checkIfPatternBind(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (parseImportDeclEnd(tokens, i)) |next_idx| {
                i = next_idx - 1;
                continue;
            }
        }

        if (!tokEq(tokens[i], "if")) continue;

        var bind_colon_idx: ?usize = null;
        var j = i + 1;
        while (j < tokens.len and (j - i) <= 48) : (j += 1) {
            if (tokEq(tokens[j], "{")) break;
            if (tokEq(tokens[j], ":") and j + 1 < tokens.len and tokEq(tokens[j + 1], "=")) {
                bind_colon_idx = j;
                break;
            }
        }
        if (bind_colon_idx == null) continue;

        const bind_idx = bind_colon_idx.?;
        if (i + 1 >= bind_idx) return markErrorAt(tokens, i, error.InvalidIfPatternBind);
        const first = tokens[i + 1];
        if (first.kind != .ident) return markErrorAt(tokens, i + 1, error.InvalidIfPatternBind);
        if (!isTypeName(first.lexeme)) return markErrorAt(tokens, i + 1, error.InvalidIfPatternBind);
        if (i + 2 >= bind_idx) return markErrorAt(tokens, i + 2, error.InvalidIfPatternBind);

        const open = tokens[i + 2];
        const close = tokens[bind_idx - 1];
        if (tokEq(open, "(") and tokEq(close, ")")) continue;
        if (tokEq(open, "{") and tokEq(close, "}")) continue;
        return markErrorAt(tokens, bind_idx, error.InvalidIfPatternBind);
    }
}

fn checkTypeDeclNaming(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (isKeyword(t.lexeme)) continue;
        if (!isTypeDeclStart(tokens, i)) continue;
        if (isValidDeclaredTypeName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeDeclName);
    }
}

fn isTopLevelDeclHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line == tokens[idx].line) return false;

    const prev = tokens[idx - 1];
    if (tokEq(prev, "=")) return false;
    if (tokEq(prev, "|")) return false;
    if (tokEq(prev, ",")) return false;
    if (tokEq(prev, ":")) return false;
    return true;
}

fn isTypeDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokEq(tokens[idx + 1], "(")) return false; // func decl

    var next_idx = idx + 1;
    if (tokEq(tokens[next_idx], "<")) {
        const close_angle = findMatching(tokens, next_idx, "<", ">") catch return false;
        next_idx = close_angle + 1;
        if (next_idx >= tokens.len) return false;
    }

    if (tokEq(tokens[next_idx], "{")) return true; // struct decl
    if (tokEq(tokens[next_idx], "=")) return true; // alias / union / typeset alias
    return false;
}

fn isValidDeclaredTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isUpper(name[0])) return false;

    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        if (std.ascii.isAlphabetic(name[i])) continue;
        if (std.ascii.isDigit(name[i])) continue;
        return false;
    }
    return true;
}

fn checkLoopHeader(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (parseImportDeclEnd(tokens, i)) |next_idx| {
                i = next_idx - 1;
                continue;
            }
        }

        if (!tokEq(tokens[i], "loop")) continue;
        const open_brace = findLoopBlockOpen(tokens, i) orelse return markErrorAt(tokens, i, error.InvalidLoopHeader);
        if (open_brace <= i) return markErrorAt(tokens, i, error.InvalidLoopHeader);

        const header_start = i + 1;
        if (open_brace == header_start) {
            i = open_brace;
            continue; // loop { ... }
        }

        const bind = findLoopBindAssign(tokens, header_start, open_brace);
        if (bind == null) {
            i = open_brace;
            continue; // loop cond { ... }
        }

        const bind_idx = bind.?;
        try validateLoopBindLhs(tokens, header_start, bind_idx);
        if (bind_idx + 2 >= open_brace) return markErrorAt(tokens, bind_idx, error.InvalidLoopHeader);
        i = open_brace;
    }
}

fn findLoopBlockOpen(tokens: []const lexer.Token, loop_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = loop_idx + 1;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0) return i;
            depth_brace += 1;
            continue;
        }
        if (!tokEq(tokens[i], "}")) continue;
        if (depth_brace > 0) depth_brace -= 1;
    }
    return null;
}

fn findLoopBindAssign(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var found: ?usize = null;
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0) break;
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (!tokEq(tokens[i], ":") or !tokEq(tokens[i + 1], "=")) continue;
        if (found != null) return null;
        found = i;
    }
    return found;
}

fn validateLoopBindLhs(tokens: []const lexer.Token, start_idx: usize, bind_idx: usize) !void {
    if (start_idx >= bind_idx) return markErrorAt(tokens, bind_idx, error.InvalidLoopHeader);
    if (tokens[start_idx].kind != .ident) return markErrorAt(tokens, start_idx, error.InvalidLoopHeader);
    if (isKeyword(tokens[start_idx].lexeme)) return markErrorAt(tokens, start_idx, error.InvalidLoopHeader);

    if (start_idx + 1 == bind_idx) return;
    if (start_idx + 3 != bind_idx) return markErrorAt(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (!tokEq(tokens[start_idx + 1], ",")) return markErrorAt(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (tokens[start_idx + 2].kind != .ident) return markErrorAt(tokens, start_idx + 2, error.InvalidLoopHeader);
    if (isKeyword(tokens[start_idx + 2].lexeme)) return markErrorAt(tokens, start_idx + 2, error.InvalidLoopHeader);
}

fn checkAssignmentConstraints(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var scopes: std.ArrayListUnmanaged(Scope) = .{};
    defer {
        for (scopes.items) |*scope| scope.deinit(allocator);
        scopes.deinit(allocator);
    }

    try scopes.append(allocator, .{});

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            try scopes.append(allocator, .{});
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (scopes.items.len <= 1) return markErrorAt(tokens, i, error.UnbalancedScope);
            var popped = scopes.pop().?;
            popped.deinit(allocator);
            continue;
        }
        if (!tokEq(tokens[i], "=")) continue;
        if (isNonAssignEqual(tokens, i)) continue;

        var line_start = i;
        while (line_start > 0 and tokens[line_start - 1].line == tokens[i].line) {
            line_start -= 1;
        }

        var k = line_start;
        while (k < i) : (k += 1) {
            const t = tokens[k];
            if (t.kind != .ident) continue;
            if (t.lexeme.len == 0) continue;

            if (t.lexeme[0] == '.') return markErrorAt(tokens, k, error.PrivateIdentCannotBeLValue);
            if (t.lexeme[0] != '_') continue;
            if (std.mem.eql(u8, t.lexeme, "_")) continue;

            var current = &scopes.items[scopes.items.len - 1];
            if (current.contains(t.lexeme)) return markErrorAt(tokens, k, error.DuplicateImmutableBinding);
            try current.names.append(allocator, t.lexeme);
        }
    }
}

fn isNonAssignEqual(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokEq(tokens[idx - 1], ":")) return true; // :=
    if (idx > 0 and tokEq(tokens[idx - 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], ">")) return true; // =>
    return false;
}

fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}

fn isKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "if",
        "else",
        "loop",
        "break",
        "continue",
        "return",
        "defer",
        "match",
        "do",
        "test",
        "true",
        "false",
        "nil",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

fn isTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isUpper(name[0]);
}

fn markErrorAt(tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror {
    if (tokens.len != 0) {
        const safe_idx = if (idx < tokens.len) idx else tokens.len - 1;
        last_error_site = .{
            .line = tokens[safe_idx].line,
            .col = tokens[safe_idx].col,
        };
    }
    return err;
}
