const std = @import("std");
const token = @import("token.zig");

pub const Lexer = struct {
    source: [:0]const u8,
    pos: usize = 0,
    line: u32 = 1,
    col: u32 = 1,

    pub fn init(source: [:0]const u8) Lexer {
        return .{ .source = source };
    }

    pub fn next(self: *Lexer) token.Token {
        self.skipWhitespace();
        const tok = self.nextImpl();
        return tok;
    }

    fn nextImpl(self: *Lexer) token.Token {
        self.skipWhitespace();

        const start = self.pos;
        const start_line = self.line;
        const start_col = self.col;

        const c = self.peek() orelse return self.makeToken(.eof, start, start_line, start_col);

        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.readIdentifier(start, start_line, start_col);
        }

        if (std.ascii.isDigit(c)) {
            return self.readNumber(start, start_line, start_col);
        }

        if (c == '"') {
            return self.readString(start, start_line, start_col);
        }

        self.advance();
        switch (c) {
            '=' => {
                if (self.match('>')) return self.makeToken(.arrow_fat, start, start_line, start_col);
                if (self.match('=')) return self.makeToken(.equal_equal, start, start_line, start_col);
                return self.makeToken(.assign, start, start_line, start_col);
            },
            ':' => {
                if (self.match('=')) return self.makeToken(.assign_init, start, start_line, start_col);
                return self.makeToken(.colon, start, start_line, start_col);
            },
            '-' => {
                if (self.match('>')) return self.makeToken(.arrow_out, start, start_line, start_col);
                return self.makeToken(.minus, start, start_line, start_col);
            },
            '<' => {
                if (self.match('-')) return self.makeToken(.arrow_in, start, start_line, start_col);
                if (self.match('<')) return self.makeToken(.l_shift, start, start_line, start_col);
                if (self.match('=')) return self.makeToken(.less_equal, start, start_line, start_col);
                return self.makeToken(.less, start, start_line, start_col);
            },
            '>' => {
                if (self.match('>')) return self.makeToken(.r_shift, start, start_line, start_col);
                if (self.match('=')) return self.makeToken(.greater_equal, start, start_line, start_col);
                return self.makeToken(.greater, start, start_line, start_col);
            },
            '!' => {
                if (self.match('=')) return self.makeToken(.not_equal, start, start_line, start_col);
                return self.makeToken(.invalid, start, start_line, start_col);
            },
            '(' => return self.makeToken(.l_paren, start, start_line, start_col),
            ')' => return self.makeToken(.r_paren, start, start_line, start_col),
            '{' => return self.makeToken(.l_brace, start, start_line, start_col),
            '}' => return self.makeToken(.r_brace, start, start_line, start_col),
            '[' => return self.makeToken(.l_bracket, start, start_line, start_col),
            ']' => return self.makeToken(.r_bracket, start, start_line, start_col),
            ',' => return self.makeToken(.comma, start, start_line, start_col),
            '#' => return self.makeToken(.hash_tag, start, start_line, start_col),
            '|' => return self.makeToken(.pipe, start, start_line, start_col),
            '+' => return self.makeToken(.plus, start, start_line, start_col),
            '*' => return self.makeToken(.asterisk, start, start_line, start_col),
            '/' => return self.makeToken(.slash, start, start_line, start_col),
            '%' => return self.makeToken(.percent, start, start_line, start_col),
            '.' => return self.makeToken(.dot, start, start_line, start_col),
            ';' => return self.makeToken(.semicolon, start, start_line, start_col),
            else => return self.makeToken(.invalid, start, start_line, start_col),
        }
    }

    fn readIdentifier(self: *Lexer, start: usize, start_line: u32, start_col: u32) token.Token {
        while (self.peek()) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.advance();
            } else {
                break;
            }
        }
        const text = self.source[start..self.pos];
        if (std.mem.eql(u8, text, "if")) return self.makeToken(.kw_if, start, start_line, start_col);
        if (std.mem.eql(u8, text, "else")) return self.makeToken(.kw_else, start, start_line, start_col);
        if (std.mem.eql(u8, text, "loop")) return self.makeToken(.kw_loop, start, start_line, start_col);
        if (std.mem.eql(u8, text, "break")) return self.makeToken(.kw_break, start, start_line, start_col);
        if (std.mem.eql(u8, text, "continue")) return self.makeToken(.kw_continue, start, start_line, start_col);
        if (std.mem.eql(u8, text, "return")) return self.makeToken(.kw_return, start, start_line, start_col);
        if (std.mem.eql(u8, text, "defer")) return self.makeToken(.kw_defer, start, start_line, start_col);
        if (std.mem.eql(u8, text, "match")) return self.makeToken(.kw_match, start, start_line, start_col);
        if (std.mem.eql(u8, text, "bool")) return self.makeToken(.kw_bool, start, start_line, start_col);

        return self.makeToken(.identifier, start, start_line, start_col);
    }

    fn readNumber(self: *Lexer, start: usize, line: u32, col: u32) token.Token {
        var is_float = false;
        while (self.peek()) |c| {
            if (std.ascii.isDigit(c)) {
                self.advance();
            } else if (c == '.' and !is_float) {
                // 仅当点号后跟数字时才视为浮点数，否则由 dot 记号处理
                if (self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
                    is_float = true;
                    self.advance();
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        return self.makeToken(if (is_float) .literal_float else .literal_int, start, line, col);
    }

    fn readString(self: *Lexer, start: usize, line: u32, col: u32) token.Token {
        self.advance();
        while (self.peek()) |c| {
            if (c == '"') {
                self.advance();
                break;
            }
            self.advance();
        }
        return self.makeToken(.literal_text, start, line, col);
    }

    fn advance(self: *Lexer) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.peek() == expected) {
            self.advance();
            return true;
        }
        return false;
    }

    fn peek(self: *Lexer) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.peek()) |c| {
            switch (c) {
                ' ', '\t', '\r', '\n' => self.advance(),
                '/' => {
                    if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                        while (self.peek() != null and self.peek() != '\n') self.advance();
                    } else {
                        break;
                    }
                },
                else => break,
            }
        }
    }

    fn makeToken(self: *Lexer, tag: token.TokenTag, start: usize, line: u32, col: u32) token.Token {
        return .{
            .tag = tag,
            .loc = .{ .start = start, .end = self.pos, .line = line, .col = col },
        };
    }
};
