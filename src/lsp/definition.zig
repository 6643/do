const std = @import("std");
const lexer = @import("../build/lexer.zig");
const protocol = @import("protocol.zig");
const source_helpers = @import("source_helpers.zig");
const brace_depth_before = source_helpers.brace_depth_before;
const token_range = source_helpers.token_range;
const is_type_name = source_helpers.is_type_name;
const is_field_name = source_helpers.is_field_name;
const is_keyword = source_helpers.is_keyword;

const workspace = @import("workspace.zig");

pub fn find_definition(
    allocator: std.mem.Allocator,
    uri: []const u8,
    source: []const u8,
    position: protocol.Position,
) !?protocol.Location {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const token_idx = token_at_position(tokens, position) orelse return null;
    const token = tokens[token_idx];
    if (token.kind != .ident) return null;
    if (is_keyword(token.lexeme) or is_field_name(token.lexeme)) return null;

    for (tokens, 0..) |candidate, idx| {
        if (!std.mem.eql(u8, candidate.lexeme, token.lexeme)) continue;
        if (!is_definition_head(tokens, idx)) continue;
        return .{
            .uri = uri,
            .range = token_range(candidate),
        };
    }

    return null;
}

pub fn find_definition_with_workspace(
    allocator: std.mem.Allocator,
    uri: []const u8,
    source: []const u8,
    position: protocol.Position,
    workspace_symbols: []const workspace.WorkspaceSymbol,
) !?protocol.Location {
    if (try find_definition(allocator, uri, source, position)) |location| return location;

    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const token_idx = token_at_position(tokens, position) orelse return null;
    const token = tokens[token_idx];
    if (token.kind != .ident) return null;
    if (is_keyword(token.lexeme) or is_field_name(token.lexeme)) return null;

    for (workspace_symbols) |symbol| {
        if (!std.mem.eql(u8, symbol.name, token.lexeme)) continue;
        return .{
            .uri = symbol.uri,
            .range = symbol.range,
        };
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

fn is_definition_head(tokens: []const lexer.Token, idx: usize) bool {
    if (brace_depth_before(tokens, idx) != 0) return false;
    return is_function_head(tokens, idx) or is_type_decl(tokens, idx);
}

fn is_function_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    const token = tokens[idx];
    const next = tokens[idx + 1];
    if (token.kind != .ident) return false;
    if (token.col != 1) return false;
    if (is_keyword(token.lexeme) or is_field_name(token.lexeme)) return false;
    if (token.line != next.line) return false;
    return next.kind == .symbol and std.mem.eql(u8, next.lexeme, "(");
}

fn is_type_decl(tokens: []const lexer.Token, idx: usize) bool {
    if (tokens[idx].kind != .ident or !is_type_name(tokens[idx].lexeme)) return false;
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

test "find_definition resolves current file function call" {
    const source =
        \\User {
        \\    title text
        \\}
        \\
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

    const location = (try find_definition(std.testing.allocator, "file:///tmp/app.do", source, .{ .line = 9, .character = 18 })).?;

    try std.testing.expectEqualStrings("file:///tmp/app.do", location.uri);
    try std.testing.expectEqual(@as(usize, 4), location.range.start.line);
    try std.testing.expectEqual(@as(usize, 0), location.range.start.character);
    try std.testing.expectEqual(@as(usize, 4), location.range.end.line);
    try std.testing.expectEqual(@as(usize, 9), location.range.end.character);
}

test "find_definition resolves current file type reference" {
    const source =
        \\User {
        \\    title text
        \\}
        \\
        \\get_title(user User) -> text {
        \\    return @get(user, .title)
        \\}
        \\
    ;

    const location = (try find_definition(std.testing.allocator, "file:///tmp/app.do", source, .{ .line = 4, .character = 15 })).?;

    try std.testing.expectEqual(@as(usize, 0), location.range.start.line);
    try std.testing.expectEqual(@as(usize, 0), location.range.start.character);
    try std.testing.expectEqual(@as(usize, 0), location.range.end.line);
    try std.testing.expectEqual(@as(usize, 4), location.range.end.character);
}

test "find_definition returns null for unknown token" {
    const source =
        \\User {
        \\    title text
        \\}
        \\
    ;

    const location = try find_definition(std.testing.allocator, "file:///tmp/app.do", source, .{ .line = 1, .character = 4 });

    try std.testing.expect(location == null);
}

test "find_definition_with_workspace resolves workspace type reference" {
    const source =
        \\make() -> ProjectUser {
        \\    return ProjectUser{}
        \\}
        \\
    ;
    const workspace_symbols = [_]workspace.WorkspaceSymbol{
        .{
            .name = "ProjectUser",
            .kind = .type_name,
            .uri = "file:///tmp/project/user.do",
            .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 11 } },
            .detail = "ProjectUser {",
        },
    };

    const location = (try find_definition_with_workspace(
        std.testing.allocator,
        "file:///tmp/project/main.do",
        source,
        .{ .line = 0, .character = 10 },
        &workspace_symbols,
    )).?;

    try std.testing.expectEqualStrings("file:///tmp/project/user.do", location.uri);
    try std.testing.expectEqual(@as(usize, 0), location.range.start.line);
    try std.testing.expectEqual(@as(usize, 0), location.range.start.character);
}
