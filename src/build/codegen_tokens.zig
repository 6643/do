const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");

pub const Range = struct {
    start: usize,
    end: usize,
};

pub fn tok_eq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}

pub fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return find_matching_in_range(tokens, open_idx, open, close, tokens.len);
}

pub fn find_matching_in_range(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= limit or !tok_eq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < limit) : (i += 1) {
        if (tok_eq(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

pub fn find_line_end(tokens: []const lexer.Token, start_idx: usize) usize {
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}

pub fn find_line_start(tokens: []const lexer.Token, idx: usize) usize {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) : (i -= 1) {}
    return i;
}

pub fn is_line_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx == 0 or tokens[idx - 1].line != tokens[idx].line;
}

pub fn hex_value(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}

pub fn decode_quoted_string_token(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
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
                const hi = hex_value(body[i + 1]) orelse return error.InvalidStringEscape;
                const lo = hex_value(body[i + 2]) orelse return error.InvalidStringEscape;
                try out.append(allocator, (hi << 4) | lo);
                i += 2;
            },
            else => return error.InvalidStringEscape,
        }
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

pub fn find_top_level_token(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], lexeme)) return i;
    }
    return null;
}

pub fn find_arg_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) return i;
    }
    return end_idx;
}

pub fn trim_parens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) Range {
    var start = start_idx;
    var end = end_idx;
    while (start + 1 < end and tok_eq(tokens[start], "(")) {
        const close = find_matching_in_range(tokens, start, "(", ")", end) catch break;
        if (close + 1 != end) break;
        start += 1;
        end -= 1;
    }
    return .{ .start = start, .end = end };
}

pub fn string_token_body(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}

pub fn compact_token_text(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        try out.appendSlice(allocator, tokens[i].lexeme);
    }

    return out.toOwnedSlice(allocator);
}

pub fn find_top_level_type_separator(ty: []const u8, sep: u8) ?usize {
    return find_top_level_type_separator_from(ty, 0, sep);
}

pub fn find_top_level_type_separator_from(ty: []const u8, start_idx: usize, sep: u8) ?usize {
    return type_util.find_top_level_type_separator_from(ty, start_idx, sep);
}

pub fn align_up(value: usize, alignment: usize) usize {
    return ((value + alignment - 1) / alignment) * alignment;
}

pub fn module_tokens_equal(a: []const lexer.Token, b: []const lexer.Token) bool {
    return a.ptr == b.ptr and a.len == b.len;
}

pub fn find_start_func(tokens: []const lexer.Token) ?usize {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, "start") and tok_eq(tokens[i + 1], "(")) return i;
    }
    return null;
}

pub fn find_token(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], lexeme)) return i;
    }
    return null;
}

pub fn find_top_level_block_open(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_angle == 0 and tok_eq(tokens[i], "{")) return i;
    }
    return null;
}

pub fn find_stmt_end(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < limit_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
        } else if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
        } else if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
        } else if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
        } else if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
        } else if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (i + 1 >= limit_idx or tokens[i + 1].line != tokens[i].line) return i + 1;
    }
    return limit_idx;
}

pub fn find_type_arg_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) return i;
    }
    return end_idx;
}

pub fn string_literal_arg_lexeme(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return null;
    const tok = tokens[range.start];
    if (tok.kind != .string) return null;
    if (tok.lexeme.len < 2 or tok.lexeme[0] != '"') return null;
    return tok.lexeme;
}

pub fn is_string_literal_arg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return string_literal_arg_lexeme(tokens, start_idx, end_idx) != null;
}

pub fn is_typed_binding_rhs_call(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    if (line_start + 3 > call_idx) return false;
    if (tokens[line_start].kind != .ident) return false;
    if (tokens[line_start + 1].kind != .ident) return false;
    const eq_idx = find_top_level_token(tokens, line_start + 2, call_idx, "=") orelse return false;
    return eq_idx + 1 == call_idx;
}

pub fn is_bare_host_call_statement(tokens: []const lexer.Token, call_idx: usize, close_paren: usize) bool {
    const line_start = find_line_start(tokens, call_idx);
    const line_end = find_line_end(tokens, call_idx);
    return line_start == call_idx and close_paren + 1 == line_end;
}

pub fn is_user_func_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!is_line_start(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[idx].lexeme, "start")) return false;
    return tok_eq(tokens[idx + 1], "(");
}

pub fn token_text_equals_compact(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
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
