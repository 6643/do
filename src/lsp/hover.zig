const std = @import("std");
const lexer = @import("../build/lexer.zig");
const protocol = @import("protocol.zig");
const source_helpers = @import("source_helpers.zig");
const brace_depth_before = source_helpers.brace_depth_before;
const line_slice = source_helpers.line_slice;
const is_type_name = source_helpers.is_type_name;
const is_field_name = source_helpers.is_field_name;
const is_keyword = source_helpers.is_keyword;


pub fn find_hover(
    allocator: std.mem.Allocator,
    source: []const u8,
    position: protocol.Position,
) !?[]u8 {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const token_idx = token_at_position(tokens, position) orelse return null;
    const token = tokens[token_idx];
    if (token.kind != .ident) return null;
    if (is_keyword(token.lexeme) or is_field_name(token.lexeme)) return null;

    if (is_top_level_function_decl(tokens, token_idx)) {
        return try function_signature(allocator, source, token.line);
    }

    for (tokens, 0..) |candidate, idx| {
        if (!std.mem.eql(u8, candidate.lexeme, token.lexeme)) continue;
        if (!is_top_level_function_decl(tokens, idx)) continue;
        return try function_signature(allocator, source, candidate.line);
    }

    // Type names (UpperCamel): hover shows the declaration head line.
    if (is_type_name(token.lexeme)) {
        for (tokens, 0..) |candidate, idx| {
            if (!std.mem.eql(u8, candidate.lexeme, token.lexeme)) continue;
            if (!is_top_level_type_decl(tokens, idx)) continue;
            return try type_decl_hover(allocator, source, candidate.line);
        }
    }

    return null;
}

fn token_at_position(tokens: []const lexer.Token, position: protocol.Position) ?usize {
    for (tokens, 0..) |token, idx| {
        if (token.line == 0 or token.col == 0) continue;
        if (token.line - 1 != position.line) continue;

        const start = token.col - 1;
        const end = start + token.lexeme.len;
        if (position.character >= start and position.character < end) return idx;
    }
    return null;
}

fn is_top_level_function_decl(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    const token = tokens[idx];
    const next = tokens[idx + 1];
    if (token.kind != .ident) return false;
    if (is_keyword(token.lexeme) or is_field_name(token.lexeme)) return false;
    if (token.line != next.line) return false;
    if (next.kind != .symbol or !std.mem.eql(u8, next.lexeme, "(")) return false;
    return brace_depth_before(tokens, idx) == 0;
}

fn is_top_level_type_decl(tokens: []const lexer.Token, idx: usize) bool {
    if (tokens[idx].kind != .ident or !is_type_name(tokens[idx].lexeme)) return false;
    if (brace_depth_before(tokens, idx) != 0) return false;
    if (tokens[idx].col != 1) return false;
    if (idx + 1 >= tokens.len) return false;
    const next = tokens[idx + 1];
    if (tokens[idx].line != next.line) return false;
    if (next.kind == .symbol and std.mem.eql(u8, next.lexeme, "{")) return true;
    if (next.kind == .symbol and std.mem.eql(u8, next.lexeme, "=")) return true;
    if (idx + 2 >= tokens.len) return false;
    const after = tokens[idx + 2];
    if (tokens[idx].line != after.line) return false;
    return after.kind == .symbol and std.mem.eql(u8, after.lexeme, "=");
}

fn type_decl_hover(allocator: std.mem.Allocator, source: []const u8, one_based_line: usize) !?[]u8 {
    const line = line_slice(source, one_based_line) orelse return null;
    const head = signature_head(line);
    if (head.len == 0) return null;
    return try allocator.dupe(u8, head);
}

fn function_signature(allocator: std.mem.Allocator, source: []const u8, one_based_line: usize) !?[]u8 {
    const line = line_slice(source, one_based_line) orelse return null;
    const head = signature_head(line);
    if (head.len == 0) return null;
    if (std.mem.indexOf(u8, head, "->") != null) return try allocator.dupe(u8, head);
    return try std.fmt.allocPrint(allocator, "{s} -> nil", .{head});
}

fn signature_head(line: []const u8) []const u8 {
    const body_start = if (std.mem.indexOf(u8, line, "{")) |idx|
        idx
    else if (std.mem.indexOf(u8, line, "=>")) |idx|
        idx
    else
        line.len;
    return std.mem.trim(u8, line[0..body_start], " \t\r\n");
}

test "find_hover returns current file function declaration signature" {
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

    const info = (try find_hover(std.testing.allocator, source, .{ .line = 3, .character = 3 })).?;
    defer std.testing.allocator.free(info);

    try std.testing.expectEqualStrings("get_title(user User) -> text", info);
}

test "find_hover returns null outside known symbols" {
    const source =
        \\User {
        \\    title text
        \\}
        \\
    ;

    const info = try find_hover(std.testing.allocator, source, .{ .line = 1, .character = 6 });
    try std.testing.expect(info == null);
}

test "find_hover resolves current file function call to declaration" {
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

    const info = (try find_hover(std.testing.allocator, source, .{ .line = 5, .character = 18 })).?;
    defer std.testing.allocator.free(info);

    try std.testing.expectEqualStrings("get_title(user User) -> text", info);
}

test "find_hover returns type declaration head for type references" {
    const source =
        \\Point {
        \\    x i32
        \\    y i32
        \\}
        \\start() {
        \\    p Point = Point{x = 1, y = 2}
        \\}
        \\
    ;

    // Hover on `Point` in the binding type position (line index 5).
    // signature_head stops before `{`, so the head is the type name.
    const info = (try find_hover(std.testing.allocator, source, .{ .line = 5, .character = 6 })).?;
    defer std.testing.allocator.free(info);
    try std.testing.expectEqualStrings("Point", info);

    // Hover on `Point` constructor call also resolves to the decl head.
    const ctor = (try find_hover(std.testing.allocator, source, .{ .line = 5, .character = 14 })).?;
    defer std.testing.allocator.free(ctor);
    try std.testing.expectEqualStrings("Point", ctor);
}
