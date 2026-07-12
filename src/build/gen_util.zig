const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");

pub const Range = struct {
    start: usize,
    end: usize,
};

pub fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}

pub fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}

pub fn findMatchingInRange(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
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

pub fn findLineEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}

pub fn findLineStart(tokens: []const lexer.Token, idx: usize) usize {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) : (i -= 1) {}
    return i;
}

pub fn isLineStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx == 0 or tokens[idx - 1].line != tokens[idx].line;
}

pub fn appendFmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

pub fn hexValue(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}

pub fn decodeQuotedStringToken(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return error.InvalidStringEscape;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    const body = raw[1 .. raw.len - 1];
    var i: usize = 0;
    while (i < body.len) {
        if (body[i] != '\\') {
            try out.append(allocator, body[i]);
            i += 1;
            continue;
        }

        i += 1;
        if (i >= body.len) return error.InvalidStringEscape;
        switch (body[i]) {
            '"' => try out.append(allocator, '"'),
            '\\' => try out.append(allocator, '\\'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            'x' => {
                if (i + 2 >= body.len) return error.InvalidStringEscape;
                const hi = hexValue(body[i + 1]) orelse return error.InvalidStringEscape;
                const lo = hexValue(body[i + 2]) orelse return error.InvalidStringEscape;
                try out.append(allocator, (hi << 4) | lo);
                i += 2;
            },
            else => return error.InvalidStringEscape,
        }
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

pub fn findTopLevelToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
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

pub fn findArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) return i;
    }
    return end_idx;
}

pub fn trimParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) Range {
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

pub fn stringTokenBody(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}

pub fn publicDeclName(name: []const u8) []const u8 {
    if (name.len > 1 and name[0] == '.') return name[1..];
    return name;
}

pub fn compactTokenText(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        try out.appendSlice(allocator, tokens[i].lexeme);
    }

    return out.toOwnedSlice(allocator);
}

pub fn hasString(items: []const []const u8, target: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, target)) return true;
    }
    return false;
}


pub fn findTopLevelTypeSeparator(ty: []const u8, sep: u8) ?usize {
    return findTopLevelTypeSeparatorFrom(ty, 0, sep);
}

pub fn findTopLevelTypeSeparatorFrom(ty: []const u8, start_idx: usize, sep: u8) ?usize {
    return type_util.findTopLevelTypeSeparatorFrom(ty, start_idx, sep);
}

pub fn alignUp(value: usize, alignment: usize) usize {
    return ((value + alignment - 1) / alignment) * alignment;
}

// --- pure helpers (from gen_lower) ---

pub fn moduleTokensEqual(a: []const lexer.Token, b: []const lexer.Token) bool {
    return a.ptr == b.ptr and a.len == b.len;
}

pub fn findStartFunc(tokens: []const lexer.Token) ?usize {
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

pub fn findToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], lexeme)) return i;
    }
    return null;
}

pub fn findTopLevelBlockOpen(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
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
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_angle == 0 and tokEq(tokens[i], "{")) return i;
    }
    return null;
}

pub fn findStmtEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
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

pub fn findTypeArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) return i;
    }
    return end_idx;
}

pub fn stringLiteralArgLexeme(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return null;
    const tok = tokens[range.start];
    if (tok.kind != .string) return null;
    if (tok.lexeme.len < 2 or tok.lexeme[0] != '"') return null;
    return tok.lexeme;
}

pub fn isStringLiteralArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return stringLiteralArgLexeme(tokens, start_idx, end_idx) != null;
}

pub fn isTypedBindingRhsCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    if (line_start + 3 > call_idx) return false;
    if (tokens[line_start].kind != .ident) return false;
    if (tokens[line_start + 1].kind != .ident) return false;
    const eq_idx = findTopLevelToken(tokens, line_start + 2, call_idx, "=") orelse return false;
    return eq_idx + 1 == call_idx;
}

pub fn isBareHostCallStatement(tokens: []const lexer.Token, call_idx: usize, close_paren: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    return line_start == call_idx and close_paren + 1 == line_end;
}

pub fn moduleScopedSymbolName(
    allocator: std.mem.Allocator,
    module_idx: usize,
    name: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try appendFmt(allocator, &out, "__mod_{d}__", .{module_idx});
    try appendMangledTypeName(allocator, &out, publicDeclName(name));
    return out.toOwnedSlice(allocator);
}

pub fn appendMangledTypeName(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    for (ty) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9')) {
            try out.append(allocator, ch);
        } else {
            try out.append(allocator, '_');
        }
    }
}

pub fn isPublicTypeName(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
}

pub fn isErrorTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "Error") or std.mem.endsWith(u8, name, "Error");
}

pub fn isBaseIntTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "i8") or
        std.mem.eql(u8, name, "i16") or
        std.mem.eql(u8, name, "i32") or
        std.mem.eql(u8, name, "i64") or
        std.mem.eql(u8, name, "u8") or
        std.mem.eql(u8, name, "u16") or
        std.mem.eql(u8, name, "u32") or
        std.mem.eql(u8, name, "u64") or
        std.mem.eql(u8, name, "isize") or
        std.mem.eql(u8, name, "usize");
}

pub fn isNumericCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "add") or
        std.mem.eql(u8, name, "sub") or
        std.mem.eql(u8, name, "mul") or
        std.mem.eql(u8, name, "div") or
        std.mem.eql(u8, name, "rem");
}

pub fn isBitwiseCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "xor") or
        std.mem.eql(u8, name, "shl") or
        std.mem.eql(u8, name, "shr") or
        std.mem.eql(u8, name, "rotl") or
        std.mem.eql(u8, name, "rotr");
}

pub fn isCountBitsCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "clz") or
        std.mem.eql(u8, name, "ctz") or
        std.mem.eql(u8, name, "popcnt");
}

pub fn isNumericUnarySelectCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "abs");
}

pub fn isNumericBinarySelectCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "min") or
        std.mem.eql(u8, name, "max");
}

pub fn isFloatUnaryCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "neg") or
        std.mem.eql(u8, name, "sqrt") or
        std.mem.eql(u8, name, "ceil") or
        std.mem.eql(u8, name, "floor") or
        std.mem.eql(u8, name, "trunc") or
        std.mem.eql(u8, name, "nearest");
}

pub fn isFloatBinaryCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "copysign");
}

pub fn isBoolSpecialFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "not");
}

pub fn isComparisonCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "eq") or
        std.mem.eql(u8, name, "ne") or
        std.mem.eql(u8, name, "lt") or
        std.mem.eql(u8, name, "le") or
        std.mem.eql(u8, name, "gt") or
        std.mem.eql(u8, name, "ge");
}

pub fn isMemoryLoadName(name: []const u8) bool {
    return std.mem.eql(u8, name, "load_u8") or
        std.mem.eql(u8, name, "load_i8") or
        std.mem.eql(u8, name, "load_u16_le") or
        std.mem.eql(u8, name, "load_i16_le") or
        std.mem.eql(u8, name, "load_u32_le") or
        std.mem.eql(u8, name, "load_i32_le") or
        std.mem.eql(u8, name, "load_u64_le") or
        std.mem.eql(u8, name, "load_i64_le");
}

pub fn isCoreWasmCallName(name: []const u8) bool {
    return std.mem.eql(u8, name, "is") or
        std.mem.eql(u8, name, "as") or
        isBoolSpecialFuncName(name) or
        isNumericCoreFuncName(name) or
        isNumericUnarySelectCoreFuncName(name) or
        isNumericBinarySelectCoreFuncName(name) or
        isComparisonCoreFuncName(name) or
        std.mem.eql(u8, name, "get") or
        std.mem.eql(u8, name, "set") or
        std.mem.eql(u8, name, "field_name") or
        std.mem.eql(u8, name, "field_index") or
        std.mem.eql(u8, name, "field_has_default") or
        std.mem.eql(u8, name, "field_get") or
        std.mem.eql(u8, name, "field_set") or
        std.mem.eql(u8, name, "len") or
        std.mem.eql(u8, name, "put") or
        isMemoryLoadName(name) or
        isBitwiseCoreFuncName(name) or
        isCountBitsCoreFuncName(name) or
        isFloatUnaryCoreFuncName(name) or
        isFloatBinaryCoreFuncName(name);
}

pub fn isCoreWasmScalar(ty: []const u8) bool {
    return type_util.isCoreWasmScalar(ty);
}

pub fn isCoreIntegerScalar(ty: []const u8) bool {
    return type_util.isCoreIntegerScalar(ty);
}

pub fn isCoreFloatScalar(ty: []const u8) bool {
    return type_util.isCoreFloatScalar(ty);
}

pub fn isUserFuncDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!isLineStart(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[idx].lexeme, "start")) return false;
    return tokEq(tokens[idx + 1], "(");
}

pub fn tokenTextEqualsCompact(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
    var offset: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const lexeme = tokens[i].lexeme;
        if (offset + lexeme.len > expected.len) return false;
        if (!std.mem.eql(u8, expected[offset .. offset + lexeme.len], lexeme)) return false;
        offset += lexeme.len;
    }
    return offset == expected.len;
}

