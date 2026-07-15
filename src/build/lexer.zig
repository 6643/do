const std = @import("std");

pub const TokenKind = enum {
    ident,
    number,
    string,
    symbol,
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    line: usize,
    col: usize,
};

const Cursor = struct {
    i: usize,
    line: usize,
    col: usize,
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    var out = try std.ArrayList(Token).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var cur: Cursor = .{ .i = 0, .line = 1, .col = 1 };

    while (cur.i < source.len) {
        const ch = source[cur.i];

        if (ch == '\r' or ch == '\n') {
            advance_line_break(source, &cur);
            continue;
        }
        if (std.ascii.isWhitespace(ch)) {
            cur.col += 1;
            cur.i += 1;
            continue;
        }
        if (ch == '/' and cur.i + 1 < source.len and source[cur.i + 1] == '/') {
            try skip_line_comment(source, &cur);
            continue;
        }
        if (ch == '/' and cur.i + 1 < source.len and source[cur.i + 1] == '*') {
            try skip_block_comment(source, &cur);
            continue;
        }

        const start = cur.i;
        const start_col = cur.col;

        if (ch == '.' and cur.i + 2 < source.len and source[cur.i + 1] == '.' and source[cur.i + 2] == '.') {
            cur.i += 3;
            cur.col += 3;
            try out.append(allocator, .{
                .kind = .symbol,
                .lexeme = source[start..cur.i],
                .line = cur.line,
                .col = start_col,
            });
            continue;
        }

        if (is_ident_start(ch)) {
            cur.i += 1;
            cur.col += 1;
            while (cur.i < source.len and is_ident_continue(source[cur.i])) {
                cur.i += 1;
                cur.col += 1;
            }
            try out.append(allocator, .{
                .kind = .ident,
                .lexeme = source[start..cur.i],
                .line = cur.line,
                .col = start_col,
            });
            continue;
        }

        if ((ch == '-' and cur.i + 1 < source.len and std.ascii.isDigit(source[cur.i + 1])) or std.ascii.isDigit(ch)) {
            try scan_number(source, &cur);
            try out.append(allocator, .{
                .kind = .number,
                .lexeme = source[start..cur.i],
                .line = cur.line,
                .col = start_col,
            });
            continue;
        }

        if (ch == '"') {
            try scan_quoted_string(source, &cur);
            try validate_quoted_string_utf8(allocator, source[start..cur.i]);
            try out.append(allocator, .{
                .kind = .string,
                .lexeme = source[start..cur.i],
                .line = cur.line,
                .col = start_col,
            });
            continue;
        }

        if (ch == '\\' and cur.i + 1 < source.len and source[cur.i + 1] == '\\') {
            const block = try scan_line_string_block(source, &cur);
            try out.append(allocator, .{
                .kind = .string,
                .lexeme = block.lexeme,
                .line = block.line,
                .col = block.col,
            });
            continue;
        }

        cur.i += 1;
        cur.col += 1;
        try out.append(allocator, .{
            .kind = .symbol,
            .lexeme = source[start..cur.i],
            .line = cur.line,
            .col = start_col,
        });
    }

    return out.toOwnedSlice(allocator);
}

fn advance_line_break(source: []const u8, cur: *Cursor) void {
    if (source[cur.i] == '\r' and cur.i + 1 < source.len and source[cur.i + 1] == '\n') {
        cur.i += 2;
    } else {
        cur.i += 1;
    }
    cur.line += 1;
    cur.col = 1;
}

fn skip_line_comment(source: []const u8, cur: *Cursor) !void {
    if (!is_line_start(source, cur.i)) return error.InvalidComment;
    cur.i += 2;
    cur.col += 2;
    while (cur.i < source.len and source[cur.i] != '\n' and source[cur.i] != '\r') {
        cur.i += 1;
        cur.col += 1;
    }
}

fn skip_block_comment(source: []const u8, cur: *Cursor) !void {
    if (!is_line_start(source, cur.i)) return error.InvalidComment;
    cur.i += 2;
    cur.col += 2;
    var closed = false;
    while (cur.i < source.len) {
        if (source[cur.i] == '*' and cur.i + 1 < source.len and source[cur.i + 1] == '/') {
            cur.i += 2;
            cur.col += 2;
            closed = true;
            break;
        }
        if (source[cur.i] == '\r' or source[cur.i] == '\n') {
            advance_line_break(source, cur);
            continue;
        }
        cur.i += 1;
        cur.col += 1;
    }
    if (!closed) return error.InvalidComment;
    if (!rest_of_line_is_whitespace(source, cur.i)) return error.InvalidComment;
}

fn scan_number(source: []const u8, cur: *Cursor) !void {
    if (source[cur.i] == '-') {
        cur.i += 1;
        cur.col += 1;
    }
    cur.i += 1;
    cur.col += 1;
    while (cur.i < source.len and std.ascii.isDigit(source[cur.i])) {
        cur.i += 1;
        cur.col += 1;
    }
    if (cur.i + 1 >= source.len or source[cur.i] != '.' or !std.ascii.isDigit(source[cur.i + 1])) return;
    cur.i += 1;
    cur.col += 1;
    while (cur.i < source.len and std.ascii.isDigit(source[cur.i])) {
        cur.i += 1;
        cur.col += 1;
    }
}

fn scan_quoted_string(source: []const u8, cur: *Cursor) !void {
    cur.i += 1;
    cur.col += 1;
    while (cur.i < source.len and source[cur.i] != '"') {
        if (source[cur.i] == '\n' or source[cur.i] == '\r') return error.UnterminatedString;
        if (source[cur.i] != '\\') {
            cur.i += 1;
            cur.col += 1;
            continue;
        }
        try consume_string_escape(source, cur);
    }
    if (cur.i >= source.len) return error.UnterminatedString;
    cur.i += 1;
    cur.col += 1;
}

fn consume_string_escape(source: []const u8, cur: *Cursor) !void {
    cur.i += 1;
    cur.col += 1;
    if (cur.i >= source.len) return error.UnterminatedString;
    const esc = source[cur.i];
    if (esc == '"' or esc == '\\' or esc == 'n' or esc == 'r' or esc == 't') {
        cur.i += 1;
        cur.col += 1;
        return;
    }
    if (esc != 'x') return error.InvalidStringEscape;
    if (cur.i + 2 >= source.len or !std.ascii.isHex(source[cur.i + 1]) or !std.ascii.isHex(source[cur.i + 2])) {
        return error.InvalidStringEscape;
    }
    cur.i += 3;
    cur.col += 3;
}

const LineStringBlock = struct {
    lexeme: []const u8,
    line: usize,
    col: usize,
};

fn scan_line_string_block(source: []const u8, cur: *Cursor) !LineStringBlock {
    const line_start = cur.line;
    const col_start = cur.col;
    const block_start = cur.i;
    var scan = cur.*;

    while (true) {
        scan.i += 2;
        scan.col += 2;
        while (scan.i < source.len and source[scan.i] != '\n' and source[scan.i] != '\r') {
            scan.i += 1;
            scan.col += 1;
        }
        if (scan.i >= source.len) break;

        var next_i = scan.i + 1;
        if (source[scan.i] == '\r' and next_i < source.len and source[next_i] == '\n') {
            next_i += 1;
        }
        var next_col: usize = 1;
        while (next_i < source.len and (source[next_i] == ' ' or source[next_i] == '\t')) : (next_i += 1) {
            next_col += 1;
        }
        if (next_i + 1 >= source.len or source[next_i] != '\\' or source[next_i + 1] != '\\') break;
        scan.i = next_i;
        scan.line += 1;
        scan.col = next_col;
    }

    if (!std.unicode.utf8ValidateSlice(source[block_start..scan.i])) return error.InvalidStringUtf8;
    cur.* = scan;
    return .{
        .lexeme = source[block_start..scan.i],
        .line = line_start,
        .col = col_start,
    };
}

fn is_ident_start(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '.';
}

fn is_ident_continue(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or std.ascii.isDigit(ch);
}

fn is_line_start(source: []const u8, idx: usize) bool {
    var i = idx;
    while (i > 0) : (i -= 1) {
        const prev = source[i - 1];
        if (prev == '\n' or prev == '\r') return true;
        if (prev != ' ' and prev != '\t') return false;
    }
    return true;
}

fn rest_of_line_is_whitespace(source: []const u8, idx: usize) bool {
    var i = idx;
    while (i < source.len) : (i += 1) {
        const ch = source[i];
        if (ch == '\n' or ch == '\r') return true;
        if (ch != ' ' and ch != '\t') return false;
    }
    return true;
}

fn validate_quoted_string_utf8(allocator: std.mem.Allocator, raw: []const u8) !void {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return error.UnterminatedString;

    var decoded = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer decoded.deinit(allocator);

    var i: usize = 1;
    const end = raw.len - 1;
    while (i < end) {
        const ch = raw[i];
        if (ch != '\\') {
            try decoded.append(allocator, ch);
            i += 1;
            continue;
        }

        i += 1;
        if (i >= end) return error.UnterminatedString;
        const esc = raw[i];
        switch (esc) {
            '"' => try decoded.append(allocator, '"'),
            '\\' => try decoded.append(allocator, '\\'),
            'n' => try decoded.append(allocator, '\n'),
            'r' => try decoded.append(allocator, '\r'),
            't' => try decoded.append(allocator, '\t'),
            'x' => {
                if (i + 2 >= end) return error.InvalidStringEscape;
                const hi = hex_value(raw[i + 1]) orelse return error.InvalidStringEscape;
                const lo = hex_value(raw[i + 2]) orelse return error.InvalidStringEscape;
                try decoded.append(allocator, hi * 16 + lo);
                i += 2;
            },
            else => return error.InvalidStringEscape,
        }
        i += 1;
    }

    if (!std.unicode.utf8ValidateSlice(decoded.items)) return error.InvalidStringUtf8;
}

fn hex_value(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}

test "dot prefixed names tokenize as single identifiers" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, ".name .normalize_name");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.ident, tokens[0].kind);
    try std.testing.expectEqualStrings(".name", tokens[0].lexeme);
    try std.testing.expectEqual(TokenKind.ident, tokens[1].kind);
    try std.testing.expectEqualStrings(".normalize_name", tokens[1].lexeme);
}

test "internal dot starts a new dot identifier" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, ".a.b");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.ident, tokens[0].kind);
    try std.testing.expectEqualStrings(".a", tokens[0].lexeme);
    try std.testing.expectEqual(TokenKind.ident, tokens[1].kind);
    try std.testing.expectEqualStrings(".b", tokens[1].lexeme);
}

test "spread token is separate from identifier" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "...rest");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.symbol, tokens[0].kind);
    try std.testing.expectEqualStrings("...", tokens[0].lexeme);
    try std.testing.expectEqual(TokenKind.ident, tokens[1].kind);
    try std.testing.expectEqualStrings("rest", tokens[1].lexeme);
}

test "loop labels keep apostrophe as separate symbol" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "'outer");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.symbol, tokens[0].kind);
    try std.testing.expectEqualStrings("'", tokens[0].lexeme);
    try std.testing.expectEqual(TokenKind.ident, tokens[1].kind);
    try std.testing.expectEqualStrings("outer", tokens[1].lexeme);
}

test "apostrophe after identifier is separate symbol" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "x'");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.ident, tokens[0].kind);
    try std.testing.expectEqualStrings("x", tokens[0].lexeme);
    try std.testing.expectEqual(TokenKind.symbol, tokens[1].kind);
    try std.testing.expectEqualStrings("'", tokens[1].lexeme);
}

test "string escape bytes must decode valid utf8" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidStringUtf8, tokenize(allocator, "\"\\xFF\""));
}

test "string escape bytes may form valid utf8" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "\"\\xE4\\xB8\\xAD\"");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenKind.string, tokens[0].kind);
}

test "line string blocks tokenize as one token" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "\\\\abc\n  \\\\def");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenKind.string, tokens[0].kind);
    try std.testing.expectEqualStrings("\\\\abc\n  \\\\def", tokens[0].lexeme);
}

test "inline rhs line string blocks tokenize as one token" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "value text = \\\\abc\n  \\\\def");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(TokenKind.string, tokens[3].kind);
    try std.testing.expectEqualStrings("\\\\abc\n  \\\\def", tokens[3].lexeme);
}

test "blank line breaks line string block" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "\\\\abc\n\n\\\\def");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqual(TokenKind.string, tokens[0].kind);
    try std.testing.expectEqualStrings("\\\\abc", tokens[0].lexeme);
    try std.testing.expectEqual(TokenKind.string, tokens[1].kind);
    try std.testing.expectEqualStrings("\\\\def", tokens[1].lexeme);
}
