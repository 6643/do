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

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    var out = try std.ArrayList(Token).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var i: usize = 0;
    var line: usize = 1;
    var col: usize = 1;

    while (i < source.len) {
        const ch = source[i];

        if (ch == '\r') {
            if (i + 1 < source.len and source[i + 1] == '\n') {
                i += 2;
            } else {
                i += 1;
            }
            line += 1;
            col = 1;
            continue;
        }
        if (ch == '\n') {
            line += 1;
            col = 1;
            i += 1;
            continue;
        }
        if (std.ascii.isWhitespace(ch)) {
            col += 1;
            i += 1;
            continue;
        }
        if (ch == '/' and i + 1 < source.len and source[i + 1] == '/') {
            if (!isLineStart(source, i)) return error.InvalidComment;
            i += 2;
            col += 2;
            while (i < source.len and source[i] != '\n' and source[i] != '\r') {
                i += 1;
                col += 1;
            }
            continue;
        }
        if (ch == '/' and i + 1 < source.len and source[i + 1] == '*') {
            if (!isLineStart(source, i)) return error.InvalidComment;
            i += 2;
            col += 2;
            var closed = false;
            while (i < source.len) {
                if (source[i] == '*' and i + 1 < source.len and source[i + 1] == '/') {
                    i += 2;
                    col += 2;
                    closed = true;
                    break;
                }
                if (source[i] == '\r') {
                    if (i + 1 < source.len and source[i + 1] == '\n') {
                        i += 2;
                    } else {
                        i += 1;
                    }
                    line += 1;
                    col = 1;
                    continue;
                }
                if (source[i] == '\n') {
                    i += 1;
                    line += 1;
                    col = 1;
                    continue;
                }
                i += 1;
                col += 1;
            }
            if (!closed) return error.InvalidComment;
            if (!restOfLineIsWhitespace(source, i)) return error.InvalidComment;
            continue;
        }

        const start = i;
        const start_col = col;

        if (ch == '.' and i + 2 < source.len and source[i + 1] == '.' and source[i + 2] == '.') {
            i += 3;
            col += 3;
            try out.append(allocator, .{
                .kind = .symbol,
                .lexeme = source[start..i],
                .line = line,
                .col = start_col,
            });
            continue;
        }

        if (isIdentStart(ch)) {
            i += 1;
            col += 1;
            while (i < source.len and isIdentContinue(source[i])) {
                i += 1;
                col += 1;
            }
            try out.append(allocator, .{
                .kind = .ident,
                .lexeme = source[start..i],
                .line = line,
                .col = start_col,
            });
            continue;
        }

        if ((ch == '-' and i + 1 < source.len and std.ascii.isDigit(source[i + 1])) or std.ascii.isDigit(ch)) {
            if (ch == '-') {
                i += 1;
                col += 1;
            }
            i += 1;
            col += 1;
            while (i < source.len and std.ascii.isDigit(source[i])) {
                i += 1;
                col += 1;
            }
            if (i + 1 < source.len and source[i] == '.' and std.ascii.isDigit(source[i + 1])) {
                i += 1;
                col += 1;
                while (i < source.len and std.ascii.isDigit(source[i])) {
                    i += 1;
                    col += 1;
                }
            }
            try out.append(allocator, .{
                .kind = .number,
                .lexeme = source[start..i],
                .line = line,
                .col = start_col,
            });
            continue;
        }

        if (ch == '"') {
            i += 1;
            col += 1;
            while (i < source.len and source[i] != '"') {
                if (source[i] == '\n' or source[i] == '\r') return error.UnterminatedString;
                if (source[i] == '\\') {
                    i += 1;
                    col += 1;
                    if (i >= source.len) return error.UnterminatedString;
                    const esc = source[i];
                    if (esc == '"' or esc == '\\' or esc == 'n' or esc == 'r' or esc == 't') {
                        i += 1;
                        col += 1;
                        continue;
                    }
                    if (esc == 'x') {
                        if (i + 2 >= source.len or !std.ascii.isHex(source[i + 1]) or !std.ascii.isHex(source[i + 2])) {
                            return error.InvalidStringEscape;
                        }
                        i += 3;
                        col += 3;
                        continue;
                    }
                    return error.InvalidStringEscape;
                }
                i += 1;
                col += 1;
            }
            if (i >= source.len) return error.UnterminatedString;
            i += 1;
            col += 1;
            try out.append(allocator, .{
                .kind = .string,
                .lexeme = source[start..i],
                .line = line,
                .col = start_col,
            });
            continue;
        }

        if (ch == '\\' and i + 1 < source.len and source[i + 1] == '\\') {
            const line_start = line;
            const col_start = col;
            const block_start = i;
            const allow_block = isLineStart(source, i);
            var cur_i = i;
            var cur_line = line;
            var cur_col = col;

            if (allow_block) {
                while (true) {
                    cur_i += 2;
                    cur_col += 2;
                    while (cur_i < source.len and source[cur_i] != '\n' and source[cur_i] != '\r') {
                        cur_i += 1;
                        cur_col += 1;
                    }

                    if (cur_i >= source.len) break;

                    var next_i = cur_i + 1;
                    if (source[cur_i] == '\r' and next_i < source.len and source[next_i] == '\n') {
                        next_i += 1;
                    }
                    var next_col: usize = 1;
                    while (next_i < source.len and (source[next_i] == ' ' or source[next_i] == '\t')) : (next_i += 1) {
                        next_col += 1;
                    }
                    if (next_i + 1 < source.len and source[next_i] == '\\' and source[next_i + 1] == '\\') {
                        cur_i = next_i;
                        cur_line += 1;
                        cur_col = next_col;
                        continue;
                    }
                    break;
                }
            } else {
                cur_i += 2;
                cur_col += 2;
                while (cur_i < source.len and source[cur_i] != '\n' and source[cur_i] != '\r') {
                    cur_i += 1;
                    cur_col += 1;
                }
            }

            try out.append(allocator, .{
                .kind = .string,
                .lexeme = source[block_start..cur_i],
                .line = line_start,
                .col = col_start,
            });
            i = cur_i;
            line = cur_line;
            col = cur_col;
            continue;
        }

        i += 1;
        col += 1;
        try out.append(allocator, .{
            .kind = .symbol,
            .lexeme = source[start..i],
            .line = line,
            .col = start_col,
        });
    }

    return out.toOwnedSlice(allocator);
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '.';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or std.ascii.isDigit(ch);
}

fn isLineStart(source: []const u8, idx: usize) bool {
    var i = idx;
    while (i > 0) : (i -= 1) {
        const prev = source[i - 1];
        if (prev == '\n' or prev == '\r') return true;
        if (prev != ' ' and prev != '\t') return false;
    }
    return true;
}

fn restOfLineIsWhitespace(source: []const u8, idx: usize) bool {
    var i = idx;
    while (i < source.len) : (i += 1) {
        const ch = source[i];
        if (ch == '\n' or ch == '\r') return true;
        if (ch != ' ' and ch != '\t') return false;
    }
    return true;
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

test "line string blocks tokenize as one token" {
    const allocator = std.testing.allocator;
    const tokens = try tokenize(allocator, "\\\\abc\n  \\\\def");
    defer allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 1), tokens.len);
    try std.testing.expectEqual(TokenKind.string, tokens[0].kind);
    try std.testing.expectEqualStrings("\\\\abc\n  \\\\def", tokens[0].lexeme);
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
