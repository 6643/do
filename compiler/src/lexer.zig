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
            i += 2;
            col += 2;
            while (i < source.len and source[i] != '\n') {
                i += 1;
                col += 1;
            }
            continue;
        }

        const start = i;
        const start_col = col;

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

        if (std.ascii.isDigit(ch)) {
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
                if (source[i] == '\n') return error.UnterminatedString;
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
    return isIdentStart(ch) or std.ascii.isDigit(ch) or ch == '\'';
}
