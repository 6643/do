const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Local = struct {
    name: []const u8,
    ty: []const u8,
};

pub fn emitWat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try emitStartFunc(allocator, tokens, &out);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

fn emitStartFunc(allocator: std.mem.Allocator, tokens: []const lexer.Token, out: *std.ArrayList(u8)) !void {
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
    try emitBody(allocator, tokens, open_body + 1, close_body, locals.items, out);
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
            try emitExpr(allocator, tokens, eq_idx + 1, stmt_end, locals, out);
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

    const op = numericWasmOp(tokens[range.start].lexeme) orelse return;
    var arg_start = range.start + 2;
    var emitted = false;
    while (arg_start < close_paren) {
        const arg_end = findArgEnd(tokens, arg_start, close_paren);
        try emitExpr(allocator, tokens, arg_start, arg_end, locals, out);
        if (emitted) try appendFmt(allocator, out, "    {s}\n", .{op});
        emitted = true;
        arg_start = arg_end;
        if (arg_start < close_paren and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
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
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, "_start") and tokEq(tokens[i + 1], "(")) return i;
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
