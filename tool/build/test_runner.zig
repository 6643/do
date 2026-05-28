const std = @import("std");
const lexer = @import("lexer.zig");

const Value = union(enum) {
    unknown,
    nil,
    bool: bool,
    int: i128,
    text: []const u8,
};

const Binding = struct {
    name: []const u8,
    value: Value,
};

const FuncDecl = struct {
    name: []const u8,
    params_start: usize,
    params_end: usize,
    param_count: usize,
    body_start: usize,
    body_end: usize,
    arrow: bool,
};

pub const TestDecl = struct {
    name_lexeme: []const u8,
    body_start: usize,
    body_end: usize,
    line: usize,
    col: usize,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const test_decls = try collectTopLevelTests(allocator, tokens);
    defer allocator.free(test_decls);

    if (test_decls.len == 0) return error.NoTestDecl;

    const funcs = try collectTopLevelFuncs(allocator, tokens);
    defer allocator.free(funcs);

    try runAndPrintTestReport(io, allocator, tokens, funcs, test_decls);
}

pub fn collectTopLevelTests(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]TestDecl {
    var out = std.ArrayList(TestDecl).empty;
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0) {
            i += 1;
            continue;
        }

        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, "test")) {
            i += 1;
            continue;
        }
        if (i + 2 >= tokens.len) return error.InvalidTestDecl;
        if (tokens[i + 1].kind != .string) return error.InvalidTestDecl;
        if (!tokEqToken(tokens[i + 2], "{")) return error.InvalidTestDecl;

        const close_brace = try findMatchingToken(tokens, i + 2, "{", "}");
        try out.append(allocator, .{
            .name_lexeme = tokens[i + 1].lexeme,
            .body_start = i + 3,
            .body_end = close_brace,
            .line = tokens[i].line,
            .col = tokens[i].col,
        });
        i = close_brace + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn collectTopLevelFuncs(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncDecl {
    var out = std.ArrayList(FuncDecl).empty;
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0 or !isFuncDeclStart(tokens, i)) {
            i += 1;
            continue;
        }

        const close_params = try findMatchingToken(tokens, i + 1, "(", ")");
        const body_start = findFuncBodyStart(tokens, close_params + 1) orelse {
            i += 1;
            continue;
        };
        if (tokEqToken(tokens[body_start], "{")) {
            const body_end = try findMatchingToken(tokens, body_start, "{", "}");
            try out.append(allocator, .{
                .name = publicFuncName(tokens[i].lexeme),
                .params_start = i + 2,
                .params_end = close_params,
                .param_count = countParamSlots(tokens, i + 2, close_params),
                .body_start = body_start + 1,
                .body_end = body_end,
                .arrow = false,
            });
            i = body_end + 1;
            continue;
        }

        const body_end = findLineEnd(tokens, body_start, tokens.len);
        try out.append(allocator, .{
            .name = publicFuncName(tokens[i].lexeme),
            .params_start = i + 2,
            .params_end = close_params,
            .param_count = countParamSlots(tokens, i + 2, close_params),
            .body_start = body_start,
            .body_end = body_end,
            .arrow = true,
        });
        i = body_end;
    }

    return out.toOwnedSlice(allocator);
}

fn runAndPrintTestReport(
    io: std.Io,
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    test_decls: []const TestDecl,
) !void {
    var out_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);

    var passed: usize = 0;
    var failed: usize = 0;
    for (test_decls) |decl| {
        const ok = try evalTest(allocator, tokens, funcs, decl);
        if (ok) {
            passed += 1;
            try out.interface.print("test {s} ... ok\n", .{decl.name_lexeme});
        } else {
            failed += 1;
            try out.interface.print("test {s} ... failed\n", .{decl.name_lexeme});
        }
    }

    if (failed == 0) {
        try out.interface.print("ok: {d} passed; 0 failed\n", .{passed});
        try out.interface.flush();
        return;
    }

    try out.interface.print("failed: {d} passed; {d} failed\n", .{ passed, failed });
    try out.interface.flush();
    return error.TestFailed;
}

fn evalTest(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    decl: TestDecl,
) !bool {
    if (hasUnsupportedControlFlow(tokens, decl.body_start, decl.body_end)) return true;

    var bindings = std.ArrayList(Binding).empty;
    defer bindings.deinit(allocator);

    var saw_known_false = false;
    var saw_unknown = false;
    var i = decl.body_start;
    while (i < decl.body_end) {
        if (tokEqToken(tokens[i], "if")) {
            const parsed = try evalIfReturn(allocator, tokens, funcs, &bindings, i, decl.body_end);
            if (parsed.returned) return true;
            if (parsed.unknown) {
                saw_unknown = true;
            } else {
                saw_known_false = true;
            }
            i = parsed.next_idx;
            continue;
        }
        if (tokEqToken(tokens[i], "return")) return true;
        if (try evalBindingLine(allocator, tokens, funcs, &bindings, i, decl.body_end)) |next_idx| {
            i = next_idx;
            continue;
        }
        i = findLineEnd(tokens, i, decl.body_end);
    }

    return saw_unknown or !saw_known_false;
}

fn hasUnsupportedControlFlow(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEqToken(tokens[i], "else")) return true;
        if (tokEqToken(tokens[i], "loop")) return true;
        if (!tokEqToken(tokens[i], "if")) continue;
        const line_end = findLineEnd(tokens, i, end_idx);
        if (findTopLevelToken(tokens, i + 1, line_end, "{") != null) return true;
    }
    return false;
}

const IfEval = struct {
    next_idx: usize,
    returned: bool,
    unknown: bool,
};

fn evalIfReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    if_idx: usize,
    limit_idx: usize,
) !IfEval {
    const line_end = findLineEnd(tokens, if_idx, limit_idx);
    const return_idx = findTopLevelToken(tokens, if_idx + 1, line_end, "return") orelse
        return .{ .next_idx = line_end, .returned = false, .unknown = true };
    const cond = try evalExpr(allocator, tokens, funcs, bindings.items, if_idx + 1, return_idx);
    if (cond == .unknown) {
        return .{ .next_idx = line_end, .returned = false, .unknown = true };
    }
    return .{
        .next_idx = line_end,
        .returned = cond == .bool and cond.bool,
        .unknown = cond != .bool,
    };
}

fn evalBindingLine(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    limit_idx: usize,
) !?usize {
    const line_end = findStmtEnd(tokens, start_idx, limit_idx);
    const eq_idx = findTopLevelToken(tokens, start_idx, line_end, "=") orelse return null;
    if (eq_idx == start_idx) return null;
    const name_idx = start_idx;
    if (tokens[name_idx].kind != .ident) return null;
    if (!isBindingName(tokens[name_idx].lexeme)) return null;

    const value = try evalExpr(allocator, tokens, funcs, bindings.items, eq_idx + 1, line_end);
    try bindings.append(allocator, .{ .name = tokens[name_idx].lexeme, .value = value });
    return line_end;
}

fn evalExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const trimmed = trimParens(tokens, start_idx, end_idx);
    if (trimmed.start >= trimmed.end) return .unknown;
    if (trimmed.end == trimmed.start + 1) return evalAtom(tokens[trimmed.start], bindings);

    if (tokens[trimmed.start].kind == .ident and trimmed.start + 1 < trimmed.end and tokEqToken(tokens[trimmed.start + 1], "(")) {
        const close_paren = findMatchingInRange(tokens, trimmed.start + 1, "(", ")", trimmed.end) catch return .unknown;
        if (close_paren + 1 != trimmed.end) return .unknown;
        return evalCall(allocator, tokens, funcs, bindings, trimmed.start, trimmed.start + 2, close_paren);
    }

    return .unknown;
}

const Range = struct {
    start: usize,
    end: usize,
};

fn trimParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) Range {
    var start = start_idx;
    var end = end_idx;
    while (start + 1 < end and tokEqToken(tokens[start], "(")) {
        const close = findMatchingInRange(tokens, start, "(", ")", end) catch break;
        if (close + 1 != end) break;
        start += 1;
        end -= 1;
    }
    return .{ .start = start, .end = end };
}

fn evalAtom(tok: lexer.Token, bindings: []const Binding) Value {
    if (tok.kind == .number) return .{ .int = parseInt(tok.lexeme) orelse return .unknown };
    if (tok.kind == .string) return .{ .text = stringBody(tok.lexeme) };
    if (tokEqToken(tok, "true")) return .{ .bool = true };
    if (tokEqToken(tok, "false")) return .{ .bool = false };
    if (tokEqToken(tok, "nil")) return .nil;
    if (tok.kind == .ident) {
        if (lookupBinding(bindings, tok.lexeme)) |value| return value;
    }
    return .unknown;
}

fn evalCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    name_idx: usize,
    args_start: usize,
    args_end: usize,
) anyerror!Value {
    const name = tokens[name_idx].lexeme;
    var args = std.ArrayList(Value).empty;
    defer args.deinit(allocator);
    try evalArgs(allocator, tokens, funcs, bindings, args_start, args_end, &args);

    if (std.mem.eql(u8, name, "eq")) {
        if (args.items.len != 2 or args.items[0] == .unknown or args.items[1] == .unknown) return .unknown;
        return .{ .bool = valueEq(args.items[0], args.items[1]) };
    }
    if (std.mem.eql(u8, name, "ne")) {
        if (args.items.len != 2 or args.items[0] == .unknown or args.items[1] == .unknown) return .unknown;
        return .{ .bool = !valueEq(args.items[0], args.items[1]) };
    }
    if (std.mem.eql(u8, name, "and")) return evalAnd(args.items);
    if (std.mem.eql(u8, name, "or")) return evalOr(args.items);
    if (std.mem.eql(u8, name, "not")) {
        if (args.items.len != 1 or args.items[0] != .bool) return .unknown;
        return .{ .bool = !args.items[0].bool };
    }
    if (findFunc(funcs, name, args.items.len) != null) {
        return evalUserFunc(allocator, tokens, funcs, name, args.items);
    }
    if (isNumericCoreName(name)) return evalNumericCore(name, args.items);
    return .unknown;
}

fn evalArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
    out: *std.ArrayList(Value),
) anyerror!void {
    var i = start_idx;
    while (i < end_idx) {
        const arg_end = findArgEnd(tokens, i, end_idx);
        try out.append(allocator, try evalExpr(allocator, tokens, funcs, bindings, i, arg_end));
        i = arg_end;
        if (i < end_idx and tokEqToken(tokens[i], ",")) i += 1;
    }
}

fn evalUserFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    name: []const u8,
    args: []const Value,
) anyerror!Value {
    const func = findFunc(funcs, name, args.len) orelse return .unknown;
    var bindings = std.ArrayList(Binding).empty;
    defer bindings.deinit(allocator);

    var arg_idx: usize = 0;
    var i = func.params_start;
    while (i < func.params_end and arg_idx < args.len) {
        const seg_end = findArgEnd(tokens, i, func.params_end);
        if (tokens[i].kind == .ident and isBindingName(tokens[i].lexeme)) {
            try bindings.append(allocator, .{ .name = tokens[i].lexeme, .value = args[arg_idx] });
        }
        arg_idx += 1;
        i = seg_end;
        if (i < func.params_end and tokEqToken(tokens[i], ",")) i += 1;
    }

    if (func.arrow) {
        return evalExpr(allocator, tokens, funcs, bindings.items, func.body_start, func.body_end);
    }

    if (hasUnsupportedControlFlow(tokens, func.body_start, func.body_end)) return .unknown;

    i = func.body_start;
    while (i < func.body_end) {
        if (tokEqToken(tokens[i], "return")) {
            const line_end = findLineEnd(tokens, i, func.body_end);
            return evalExpr(allocator, tokens, funcs, bindings.items, i + 1, line_end);
        }
        if (try evalBindingLine(allocator, tokens, funcs, &bindings, i, func.body_end)) |next_idx| {
            i = next_idx;
            continue;
        }
        i = findLineEnd(tokens, i, func.body_end);
    }
    return .unknown;
}

fn evalAnd(args: []const Value) Value {
    if (args.len == 0) return .{ .bool = true };
    var saw_unknown = false;
    for (args) |arg| {
        if (arg == .unknown) {
            saw_unknown = true;
            continue;
        }
        if (arg != .bool) return .unknown;
        if (!arg.bool) return .{ .bool = false };
    }
    if (saw_unknown) return .unknown;
    return .{ .bool = true };
}

fn evalOr(args: []const Value) Value {
    if (args.len == 0) return .{ .bool = false };
    var saw_unknown = false;
    for (args) |arg| {
        if (arg == .unknown) {
            saw_unknown = true;
            continue;
        }
        if (arg != .bool) return .unknown;
        if (arg.bool) return .{ .bool = true };
    }
    if (saw_unknown) return .unknown;
    return .{ .bool = false };
}

fn evalNumericCore(name: []const u8, args: []const Value) Value {
    if (args.len < 2) return .unknown;
    if (args[0] != .int) return .unknown;
    var out = args[0].int;
    for (args[1..]) |arg| {
        if (arg != .int) return .unknown;
        if (std.mem.eql(u8, name, "add")) out += arg.int else if (std.mem.eql(u8, name, "sub")) out -= arg.int else if (std.mem.eql(u8, name, "mul")) out *= arg.int else if (std.mem.eql(u8, name, "div")) {
            if (arg.int == 0) return .unknown;
            out = @divTrunc(out, arg.int);
        } else if (std.mem.eql(u8, name, "rem")) {
            if (arg.int == 0) return .unknown;
            out = @rem(out, arg.int);
        } else return .unknown;
    }
    return .{ .int = out };
}

fn valueEq(a: Value, b: Value) bool {
    if (a == .unknown or b == .unknown) return false;
    if (a == .nil and b == .nil) return true;
    if (a == .bool and b == .bool) return a.bool == b.bool;
    if (a == .int and b == .int) return a.int == b.int;
    if (a == .text and b == .text) return std.mem.eql(u8, a.text, b.text);
    return false;
}

fn lookupBinding(bindings: []const Binding, name: []const u8) ?Value {
    var i = bindings.len;
    while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, bindings[i].name, name)) return bindings[i].value;
    }
    return null;
}

fn findFunc(funcs: []const FuncDecl, name: []const u8, arg_count: usize) ?FuncDecl {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (func.param_count != arg_count) continue;
        return func;
    }
    return null;
}

fn countParamSlots(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var i = start_idx;
    while (i < end_idx) {
        const seg_end = findArgEnd(tokens, i, end_idx);
        if (seg_end > i) count += 1;
        i = seg_end;
        if (i < end_idx and tokEqToken(tokens[i], ",")) i += 1;
    }
    return count;
}

fn findFuncBodyStart(tokens: []const lexer.Token, start_idx: usize) ?usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEqToken(tokens[i], "{")) return i;
        if (i + 1 < tokens.len and tokEqToken(tokens[i], "=") and tokEqToken(tokens[i + 1], ">")) return i + 2;
    }
    return null;
}

fn findArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEqToken(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEqToken(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn findTopLevelToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEqToken(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEqToken(tokens[i], lexeme)) return i;
    }
    return null;
}

fn findLineEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    if (start_idx >= limit_idx) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < limit_idx and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn findStmtEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < limit_idx) : (i += 1) {
        if (tokEqToken(tokens[i], "(")) {
            depth_paren += 1;
        } else if (tokEqToken(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
        } else if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
        } else if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
        } else if (tokEqToken(tokens[i], "<")) {
            depth_angle += 1;
        } else if (tokEqToken(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (i + 1 >= limit_idx or tokens[i + 1].line != tokens[i].line) return i + 1;
    }
    return limit_idx;
}

fn findMatchingToken(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}

fn findMatchingInRange(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= limit or !tokEqToken(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < limit) : (i += 1) {
        if (tokEqToken(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tokEqToken(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn parseInt(raw: []const u8) ?i128 {
    if (raw.len == 0) return null;
    return std.fmt.parseInt(i128, raw, 10) catch null;
}

fn stringBody(raw: []const u8) []const u8 {
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
    return raw;
}

fn isNumericCoreName(name: []const u8) bool {
    return std.mem.eql(u8, name, "add") or
        std.mem.eql(u8, name, "sub") or
        std.mem.eql(u8, name, "mul") or
        std.mem.eql(u8, name, "div") or
        std.mem.eql(u8, name, "rem");
}

fn isFuncDeclStart(tokens: []const lexer.Token, i: usize) bool {
    if (i + 1 >= tokens.len) return false;
    if (tokens[i].kind != .ident) return false;
    if (tokEqToken(tokens[i], "test")) return false;
    if (!isFuncDeclName(tokens[i].lexeme)) return false;
    return tokEqToken(tokens[i + 1], "(");
}

fn publicFuncName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn isFuncDeclName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (isLowerIdentName(name)) return true;
    if (name[0] == '.') return isLowerIdentName(name[1..]);
    return false;
}

fn isBindingName(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isLower(name[0]) or name[0] == '_';
}

fn isLowerIdentName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isLower(name[0])) return false;

    var prev_underscore = false;
    for (name[1..]) |ch| {
        if (ch == '_') {
            if (prev_underscore) return false;
            prev_underscore = true;
            continue;
        }
        if (!std.ascii.isLower(ch) and !std.ascii.isDigit(ch)) return false;
        prev_underscore = false;
    }

    return !prev_underscore;
}

fn tokEqToken(tok: lexer.Token, lexeme: []const u8) bool {
    return std.mem.eql(u8, tok.lexeme, lexeme);
}

test "private function declaration is callable by public name" {
    const allocator = std.testing.allocator;
    const source =
        \\.double(x i32) i32 => mul(x, 2)
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collectTopLevelFuncs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), funcs.len);
    try std.testing.expectEqualStrings("double", funcs[0].name);
    try std.testing.expect(findFunc(funcs, "double", 1) != null);
}
