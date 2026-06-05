const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Local = struct {
    name: []const u8,
    ty: []const u8,
};

const HostImport = struct {
    alias: []const u8,
    field: []const u8,
    params: []const []const u8,
    result: ?[]const u8,
};

pub fn emitWat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try checkUnsupportedWasiHostImports(tokens);

    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        freeHostImports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try collectEnvHostImports(allocator, tokens, &host_imports);
    try validateHostImportBuildUses(tokens, host_imports.items);

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try emitHostImports(allocator, &out, host_imports.items);
    try emitStartFunc(allocator, tokens, host_imports.items, &out);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

fn emitStartFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    host_imports: []const HostImport,
    out: *std.ArrayList(u8),
) !void {
    const start_idx = findStartFunc(tokens) orelse return;
    const open_params = start_idx + 1;
    const close_params = try findMatching(tokens, open_params, "(", ")");
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse return;
    const close_body = try findMatching(tokens, open_body, "{", "}");

    var locals = std.ArrayList(Local).empty;
    defer locals.deinit(allocator);
    try collectI32Locals(allocator, tokens, open_body + 1, close_body, &locals);

    try out.appendSlice(allocator, "  (func $_start\n");
    for (locals.items) |local| {
        try appendFmt(allocator, out, "    (local ${s} {s})\n", .{ local.name, wasmType(local.ty) });
    }
    try emitBody(allocator, tokens, open_body + 1, close_body, locals.items, host_imports, out);
    try out.appendSlice(allocator, "  )\n");
    try out.appendSlice(allocator, "  (export \"_start\" (func $_start))\n");
}

fn collectI32Locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    out: *std.ArrayList(Local),
) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (isTypedI32Binding(tokens, i, stmt_end)) {
            try out.append(allocator, .{ .name = tokens[i].lexeme, .ty = tokens[i + 1].lexeme });
        }
        i = stmt_end;
    }
}

fn emitBody(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: []const Local,
    host_imports: []const HostImport,
    out: *std.ArrayList(u8),
) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (isTypedI32Binding(tokens, i, stmt_end)) {
            const eq_idx = findTopLevelToken(tokens, i, stmt_end, "=") orelse {
                i = stmt_end;
                continue;
            };
            try emitExpr(allocator, tokens, eq_idx + 1, stmt_end, locals, host_imports, out);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{tokens[i].lexeme});
        }
        i = stmt_end;
    }
}

fn emitExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: []const Local,
    host_imports: []const HostImport,
    out: *std.ArrayList(u8),
) !void {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .number) {
            try appendFmt(allocator, out, "    i32.const {s}\n", .{tok.lexeme});
            return;
        }
        if (tok.kind == .ident and hasLocal(locals, tok.lexeme)) {
            try appendFmt(allocator, out, "    local.get ${s}\n", .{tok.lexeme});
        }
        return;
    }

    if (tokens[range.start].kind != .ident) return;
    if (range.start + 1 >= range.end or !tokEq(tokens[range.start + 1], "(")) return;
    const close_paren = findMatchingInRange(tokens, range.start + 1, "(", ")", range.end) catch return;
    if (close_paren + 1 != range.end) return;

    if (numericWasmOp(tokens[range.start].lexeme)) |op| {
        var arg_start = range.start + 2;
        var emitted = false;
        while (arg_start < close_paren) {
            const arg_end = findArgEnd(tokens, arg_start, close_paren);
            try emitExpr(allocator, tokens, arg_start, arg_end, locals, host_imports, out);
            if (emitted) try appendFmt(allocator, out, "    {s}\n", .{op});
            emitted = true;
            arg_start = arg_end;
            if (arg_start < close_paren and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        return;
    }

    const host_import = findHostImport(host_imports, tokens[range.start].lexeme) orelse return;
    var arg_start = range.start + 2;
    while (arg_start < close_paren) {
        const arg_end = findArgEnd(tokens, arg_start, close_paren);
        try emitExpr(allocator, tokens, arg_start, arg_end, locals, host_imports, out);
        arg_start = arg_end;
        if (arg_start < close_paren and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    try appendFmt(allocator, out, "    call ${s}\n", .{host_import.alias});
}

fn collectEnvHostImports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(HostImport),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isLineStart(tokens, i)) continue;
        if (!isEnvHostImportStart(tokens, i)) continue;

        const line_end = findLineEnd(tokens, i);
        const import = try parseEnvHostImport(allocator, tokens, i, line_end);
        errdefer allocator.free(import.params);
        try out.append(allocator, import);
        i = line_end - 1;
    }
}

fn parseEnvHostImport(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    line_end: usize,
) !HostImport {
    const alias = tokens[start_idx].lexeme;
    const field = tokens[start_idx + 5].lexeme;
    const open_idx = start_idx + 6;
    const close_idx = try findMatchingInRange(tokens, open_idx, "(", ")", line_end);

    var params = std.ArrayList([]const u8).empty;
    errdefer params.deinit(allocator);

    var i = open_idx + 1;
    while (i < close_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        try params.append(allocator, tokens[i].lexeme);
        i += 1;
        if (i < close_idx and tokEq(tokens[i], ",")) i += 1;
    }

    if (close_idx + 3 >= line_end or !tokEq(tokens[close_idx + 1], "-") or !tokEq(tokens[close_idx + 2], ">")) {
        return error.InvalidImportDecl;
    }
    const result_tok = tokens[close_idx + 3].lexeme;
    const result: ?[]const u8 = if (std.mem.eql(u8, result_tok, "nil")) null else result_tok;

    return .{
        .alias = alias,
        .field = field,
        .params = try params.toOwnedSlice(allocator),
        .result = result,
    };
}

fn emitHostImports(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    host_imports: []const HostImport,
) !void {
    for (host_imports) |host_import| {
        try appendFmt(allocator, out, "  (import \"env\" \"{s}\" (func ${s}", .{ host_import.field, host_import.alias });
        if (host_import.params.len != 0) {
            try out.appendSlice(allocator, " (param");
            for (host_import.params) |param| {
                try appendFmt(allocator, out, " {s}", .{wasmType(param)});
            }
            try out.appendSlice(allocator, ")");
        }
        if (host_import.result) |result| {
            try appendFmt(allocator, out, " (result {s})", .{wasmType(result)});
        }
        try out.appendSlice(allocator, "))\n");
    }
}

fn validateHostImportBuildUses(tokens: []const lexer.Token, host_imports: []const HostImport) !void {
    if (host_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const host_import = findHostImport(host_imports, tokens[i].lexeme) orelse continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        const arg_count = countCallArgs(tokens, i + 2, close_paren);
        if (arg_count != host_import.params.len) return error.NoMatchingCall;
        if (isTypedBindingRhsCall(tokens, i) and host_import.result == null) return error.NoMatchingCall;
        i = close_paren;
    }
}

fn freeHostImports(allocator: std.mem.Allocator, host_imports: []const HostImport) void {
    for (host_imports) |host_import| {
        allocator.free(host_import.params);
    }
}

fn checkUnsupportedWasiHostImports(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isLineStart(tokens, i)) continue;
        if (isWasiHostImportStart(tokens, i)) return error.UnsupportedWasiHostImport;
    }
}

fn findHostImport(host_imports: []const HostImport, alias: []const u8) ?HostImport {
    for (host_imports) |host_import| {
        if (std.mem.eql(u8, host_import.alias, alias)) return host_import;
    }
    return null;
}

fn isEnvHostImportStart(tokens: []const lexer.Token, idx: usize) bool {
    const line_end = findLineEnd(tokens, idx);
    if (idx + 6 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "env")) return false;
    if (!tokEq(tokens[idx + 4], "/")) return false;
    if (tokens[idx + 5].kind != .ident) return false;
    return tokEq(tokens[idx + 6], "(");
}

fn isWasiHostImportStart(tokens: []const lexer.Token, idx: usize) bool {
    const line_end = findLineEnd(tokens, idx);
    if (idx + 4 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "wasi")) return false;
    return tokEq(tokens[idx + 4], "/");
}

fn isLineStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx == 0 or tokens[idx - 1].line != tokens[idx].line;
}

fn findLineEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn countCallArgs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;

    var count: usize = 1;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) count += 1;
    }
    return count;
}

fn isTypedBindingRhsCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    if (line_start + 3 > call_idx) return false;
    if (tokens[line_start].kind != .ident) return false;
    if (tokens[line_start + 1].kind != .ident) return false;
    const eq_idx = findTopLevelToken(tokens, line_start + 2, call_idx, "=") orelse return false;
    return eq_idx + 1 == call_idx;
}

fn findLineStart(tokens: []const lexer.Token, idx: usize) usize {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) : (i -= 1) {}
    return i;
}

const Range = struct {
    start: usize,
    end: usize,
};

fn trimParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) Range {
    var start = start_idx;
    var end = end_idx;
    while (start + 1 < end and tokEq(tokens[start], "(")) {
        const close = findMatchingInRange(tokens, start, "(", ")", end) catch break;
        if (close + 1 != end) break;
        start += 1;
        end -= 1;
    }
    return .{ .start = start, .end = end };
}

fn isTypedI32Binding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 3 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[start_idx + 1].lexeme, "i32")) return false;
    return findTopLevelToken(tokens, start_idx + 2, end_idx, "=") != null;
}

fn wasmType(ty: []const u8) []const u8 {
    if (std.mem.eql(u8, ty, "i32")) return "i32";
    if (std.mem.eql(u8, ty, "i64")) return "i64";
    if (std.mem.eql(u8, ty, "f32")) return "f32";
    if (std.mem.eql(u8, ty, "f64")) return "f64";
    return "i32";
}

fn numericWasmOp(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "add")) return "i32.add";
    if (std.mem.eql(u8, name, "sub")) return "i32.sub";
    if (std.mem.eql(u8, name, "mul")) return "i32.mul";
    if (std.mem.eql(u8, name, "div")) return "i32.div_s";
    if (std.mem.eql(u8, name, "rem")) return "i32.rem_s";
    return null;
}

fn hasLocal(locals: []const Local, name: []const u8) bool {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return true;
    }
    return false;
}

fn findStartFunc(tokens: []const lexer.Token) ?usize {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, "start") and tokEq(tokens[i + 1], "(")) return i;
    }
    return null;
}

fn findToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], lexeme)) return i;
    }
    return null;
}

fn findTopLevelToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], lexeme)) return i;
    }
    return null;
}

fn findStmtEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < limit_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
        } else if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
        } else if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
        } else if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
        } else if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
        } else if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (i + 1 >= limit_idx or tokens[i + 1].line != tokens[i].line) return i + 1;
    }
    return limit_idx;
}

fn findArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (depth_paren == 0 and tokEq(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}

fn findMatchingInRange(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= limit or !tokEq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < limit) : (i += 1) {
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

fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}

fn appendFmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
