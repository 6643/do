//! Shared source classification and source-range helpers for LSP features.
const std = @import("std");
const lexer = @import("../build/lexer.zig");
const protocol = @import("protocol.zig");

pub fn is_type_name(name: []const u8) bool {
    return name.len > 0 and std.ascii.isUpper(name[0]);
}

pub fn is_field_name(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}

pub fn is_keyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "if", "else", "loop", "break", "continue", "return",
        "defer", "do", "test", "true", "false", "nil",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, keyword, name)) return true;
    }
    return false;
}

pub fn line_slice(source: []const u8, one_based_line: usize) ?[]const u8 {
    if (one_based_line == 0) return null;

    var line: usize = 1;
    var start: usize = 0;
    for (source, 0..) |ch, idx| {
        if (line == one_based_line and ch == '\n') return source[start..idx];
        if (ch == '\n') {
            line += 1;
            start = idx + 1;
        }
    }

    if (line == one_based_line) return source[start..];
    return null;
}

pub fn zero_based_line_slice(source: []const u8, zero_based_line: usize) ?[]const u8 {
    return line_slice(source, zero_based_line + 1);
}

pub fn signature_head(source: []const u8, one_based_line: usize) ?[]const u8 {
    const line = line_slice(source, one_based_line) orelse return null;
    const body_start = if (std.mem.indexOf(u8, line, "{")) |idx|
        idx
    else if (std.mem.indexOf(u8, line, "=>")) |idx|
        idx
    else
        line.len;
    return std.mem.trim(u8, line[0..body_start], " \t\r\n");
}

pub fn declaration_head(source: []const u8, one_based_line: usize) ?[]const u8 {
    const line = line_slice(source, one_based_line) orelse return null;
    return std.mem.trim(u8, line, " \t\r\n");
}

pub fn token_range(token: lexer.Token) protocol.Range {
    const line = if (token.line == 0) 0 else token.line - 1;
    const start = if (token.col == 0) 0 else token.col - 1;
    return .{
        .start = .{ .line = line, .character = start },
        .end = .{ .line = line, .character = start + token.lexeme.len },
    };
}

pub fn brace_depth_before(tokens: []const lexer.Token, idx: usize) usize {
    var depth: usize = 0;
    for (tokens[0..idx]) |token| {
        if (token.kind != .symbol) continue;
        if (std.mem.eql(u8, token.lexeme, "{")) {
            depth += 1;
            continue;
        }
        if (std.mem.eql(u8, token.lexeme, "}") and depth > 0) depth -= 1;
    }
    return depth;
}
