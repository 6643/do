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
    column: usize,
    span_start: usize,
    span_end: usize,
};

pub const LexerError = error{
    InvalidPunctuation,
    InvalidStringEscape,
    InvalidStringUtf8,
    UnterminatedComment,
    UnterminatedString,
};

const Cursor = struct {
    index: usize,
    line: usize,
    column: usize,
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) (LexerError || std.mem.Allocator.Error)![]Token {
    var tokens = std.ArrayList(Token).empty;
    errdefer tokens.deinit(allocator);

    var cursor: Cursor = .{ .index = 0, .line = 1, .column = 1 };
    while (cursor.index < source.len) {
        const ch = source[cursor.index];
        if (ch == '\n' or ch == '\r') {
            advance_line(source, &cursor);
            continue;
        }
        if (ch == ' ' or ch == '\t' or ch == 0x0c) {
            cursor.index += 1;
            cursor.column += 1;
            continue;
        }
        if (ch == '/' and cursor.index + 1 < source.len and source[cursor.index + 1] == '/') {
            skip_line_comment(source, &cursor);
            continue;
        }
        if (ch == '/' and cursor.index + 1 < source.len and source[cursor.index + 1] == '*') {
            try skip_block_comment(source, &cursor);
            continue;
        }

        const start = cursor.index;
        const line = cursor.line;
        const column = cursor.column;

        if (is_identifier_start(ch)) {
            cursor.index += 1;
            cursor.column += 1;
            while (cursor.index < source.len and is_identifier_continue(source[cursor.index])) {
                cursor.index += 1;
                cursor.column += 1;
            }
            try tokens.append(allocator, .{
                .kind = .ident,
                .lexeme = source[start..cursor.index],
                .line = line,
                .column = column,
                .span_start = start,
                .span_end = cursor.index,
            });
            continue;
        }

        if (std.ascii.isDigit(ch)) {
            scan_number(source, &cursor);
            try tokens.append(allocator, .{
                .kind = .number,
                .lexeme = source[start..cursor.index],
                .line = line,
                .column = column,
                .span_start = start,
                .span_end = cursor.index,
            });
            continue;
        }

        if (ch == '"') {
            try scan_string(source, &cursor);
            try tokens.append(allocator, .{
                .kind = .string,
                .lexeme = source[start..cursor.index],
                .line = line,
                .column = column,
                .span_start = start,
                .span_end = cursor.index,
            });
            continue;
        }

        if (ch == '-' and cursor.index + 1 < source.len and source[cursor.index + 1] == '>') {
            cursor.index += 2;
            cursor.column += 2;
            try append_symbol(allocator, &tokens, source, start, cursor, line, column);
            continue;
        }

        if (is_symbol(ch)) {
            cursor.index += 1;
            cursor.column += 1;
            try append_symbol(allocator, &tokens, source, start, cursor, line, column);
            continue;
        }

        return error.InvalidPunctuation;
    }

    return tokens.toOwnedSlice(allocator);
}

fn append_symbol(
    allocator: std.mem.Allocator,
    tokens: *std.ArrayList(Token),
    source: []const u8,
    start: usize,
    cursor: Cursor,
    line: usize,
    column: usize,
) !void {
    try tokens.append(allocator, .{
        .kind = .symbol,
        .lexeme = source[start..cursor.index],
        .line = line,
        .column = column,
        .span_start = start,
        .span_end = cursor.index,
    });
}

fn is_identifier_start(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn is_identifier_continue(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-';
}

fn is_symbol(ch: u8) bool {
    return switch (ch) {
        '{', '}', '(', ')', '[', ']', '<', '>', ':', ';', ',', '.', '@', '=', '|', '?', '*' => true,
        else => false,
    };
}

fn scan_number(source: []const u8, cursor: *Cursor) void {
    while (cursor.index < source.len and std.ascii.isDigit(source[cursor.index])) {
        cursor.index += 1;
        cursor.column += 1;
    }
    while (cursor.index + 1 < source.len and source[cursor.index] == '.' and std.ascii.isDigit(source[cursor.index + 1])) {
        cursor.index += 1;
        cursor.column += 1;
        while (cursor.index < source.len and std.ascii.isDigit(source[cursor.index])) {
            cursor.index += 1;
            cursor.column += 1;
        }
    }
    if (cursor.index < source.len and source[cursor.index] == '-') {
        cursor.index += 1;
        cursor.column += 1;
        while (cursor.index < source.len and is_identifier_continue(source[cursor.index])) {
            cursor.index += 1;
            cursor.column += 1;
        }
    }
}

fn scan_string(source: []const u8, cursor: *Cursor) LexerError!void {
    cursor.index += 1;
    cursor.column += 1;
    while (cursor.index < source.len) {
        const ch = source[cursor.index];
        if (ch == '"') {
            cursor.index += 1;
            cursor.column += 1;
            return;
        }
        if (ch == '\n' or ch == '\r') return error.UnterminatedString;
        if (ch != '\\') {
            cursor.index += 1;
            cursor.column += 1;
            continue;
        }
        cursor.index += 1;
        cursor.column += 1;
        if (cursor.index >= source.len) return error.UnterminatedString;
        const escape = source[cursor.index];
        if (escape == '"' or escape == '\\' or escape == 'n' or escape == 'r' or escape == 't') {
            cursor.index += 1;
            cursor.column += 1;
            continue;
        }
        return error.InvalidStringEscape;
    }
    return error.UnterminatedString;
}

fn skip_line_comment(source: []const u8, cursor: *Cursor) void {
    while (cursor.index < source.len and source[cursor.index] != '\n' and source[cursor.index] != '\r') {
        cursor.index += 1;
        cursor.column += 1;
    }
}

fn skip_block_comment(source: []const u8, cursor: *Cursor) LexerError!void {
    cursor.index += 2;
    cursor.column += 2;
    while (cursor.index < source.len) {
        if (source[cursor.index] == '*' and cursor.index + 1 < source.len and source[cursor.index + 1] == '/') {
            cursor.index += 2;
            cursor.column += 2;
            return;
        }
        if (source[cursor.index] == '\n' or source[cursor.index] == '\r') {
            advance_line(source, cursor);
        } else {
            cursor.index += 1;
            cursor.column += 1;
        }
    }
    return error.UnterminatedComment;
}

fn advance_line(source: []const u8, cursor: *Cursor) void {
    if (source[cursor.index] == '\r' and cursor.index + 1 < source.len and source[cursor.index + 1] == '\n') {
        cursor.index += 2;
    } else {
        cursor.index += 1;
    }
    cursor.line += 1;
    cursor.column = 1;
}

test "wit lexer skips comments" {
    const tokens = try tokenize(std.testing.allocator, "// comment\npackage x:y@1.0.0; /* block */ world w {}");
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqualStrings("package", tokens[0].lexeme);
    try std.testing.expectEqual(@as(usize, 2), tokens[0].line);
}
