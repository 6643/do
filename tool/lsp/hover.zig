const std = @import("std");
const lexer = @import("../build/lexer.zig");
const protocol = @import("protocol.zig");

pub fn findHover(
    allocator: std.mem.Allocator,
    source: []const u8,
    position: protocol.Position,
) !?[]u8 {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const token_idx = tokenAtPosition(tokens, position) orelse return null;
    const token = tokens[token_idx];
    if (token.kind != .ident) return null;
    if (isKeyword(token.lexeme) or isFieldName(token.lexeme)) return null;

    if (isTopLevelFunctionDecl(tokens, token_idx)) {
        return try functionSignature(allocator, source, token.line);
    }

    for (tokens, 0..) |candidate, idx| {
        if (!std.mem.eql(u8, candidate.lexeme, token.lexeme)) continue;
        if (!isTopLevelFunctionDecl(tokens, idx)) continue;
        return try functionSignature(allocator, source, candidate.line);
    }

    return null;
}

fn tokenAtPosition(tokens: []const lexer.Token, position: protocol.Position) ?usize {
    for (tokens, 0..) |token, idx| {
        if (token.line == 0 or token.col == 0) continue;
        if (token.line - 1 != position.line) continue;

        const start = token.col - 1;
        const end = start + token.lexeme.len;
        if (position.character >= start and position.character < end) return idx;
    }
    return null;
}

fn isTopLevelFunctionDecl(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    const token = tokens[idx];
    const next = tokens[idx + 1];
    if (token.kind != .ident) return false;
    if (isKeyword(token.lexeme) or isFieldName(token.lexeme)) return false;
    if (token.line != next.line) return false;
    if (next.kind != .symbol or !std.mem.eql(u8, next.lexeme, "(")) return false;
    return braceDepthBefore(tokens, idx) == 0;
}

fn braceDepthBefore(tokens: []const lexer.Token, idx: usize) usize {
    var depth: usize = 0;
    for (tokens[0..idx]) |token| {
        if (token.kind != .symbol) continue;
        if (std.mem.eql(u8, token.lexeme, "{")) {
            depth += 1;
            continue;
        }
        if (std.mem.eql(u8, token.lexeme, "}")) {
            if (depth > 0) depth -= 1;
        }
    }
    return depth;
}

fn functionSignature(allocator: std.mem.Allocator, source: []const u8, one_based_line: usize) !?[]u8 {
    const line = lineSlice(source, one_based_line) orelse return null;
    const head = signatureHead(line);
    if (head.len == 0) return null;
    if (std.mem.indexOf(u8, head, "->") != null) return try allocator.dupe(u8, head);
    return try std.fmt.allocPrint(allocator, "{s} -> nil", .{head});
}

fn lineSlice(source: []const u8, one_based_line: usize) ?[]const u8 {
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

fn signatureHead(line: []const u8) []const u8 {
    const body_start = if (std.mem.indexOf(u8, line, "{")) |idx|
        idx
    else if (std.mem.indexOf(u8, line, "=>")) |idx|
        idx
    else
        line.len;
    return std.mem.trim(u8, line[0..body_start], " \t\r\n");
}

fn isFieldName(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}

fn isKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "if",
        "else",
        "loop",
        "break",
        "continue",
        "return",
        "defer",
        "do",
        "test",
        "true",
        "false",
        "nil",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, kw, name)) return true;
    }
    return false;
}

test "findHover returns current file function declaration signature" {
    const source =
        \\User {
        \\    title text
        \\}
        \\get_title(user User) -> text {
        \\    title text = @get(user, .title)
        \\    return title
        \\}
        \\
    ;

    const info = (try findHover(std.testing.allocator, source, .{ .line = 3, .character = 3 })).?;
    defer std.testing.allocator.free(info);

    try std.testing.expectEqualStrings("get_title(user User) -> text", info);
}

test "findHover returns null outside known symbols" {
    const source =
        \\User {
        \\    title text
        \\}
        \\
    ;

    const info = try findHover(std.testing.allocator, source, .{ .line = 1, .character = 6 });
    try std.testing.expect(info == null);
}

test "findHover resolves current file function call to declaration" {
    const source =
        \\get_title(user User) -> text {
        \\    return @get(user, .title)
        \\}
        \\
        \\test "call" {
        \\    value text = get_title(User{ title: "a" })
        \\    return
        \\}
        \\
    ;

    const info = (try findHover(std.testing.allocator, source, .{ .line = 5, .character = 18 })).?;
    defer std.testing.allocator.free(info);

    try std.testing.expectEqualStrings("get_title(user User) -> text", info);
}
