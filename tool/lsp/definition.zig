const std = @import("std");
const lexer = @import("../build/lexer.zig");
const protocol = @import("protocol.zig");
const workspace = @import("workspace.zig");

pub fn findDefinition(
    allocator: std.mem.Allocator,
    uri: []const u8,
    source: []const u8,
    position: protocol.Position,
) !?protocol.Location {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const token_idx = tokenAtPosition(tokens, position) orelse return null;
    const token = tokens[token_idx];
    if (token.kind != .ident) return null;
    if (isKeyword(token.lexeme) or isFieldName(token.lexeme)) return null;

    for (tokens, 0..) |candidate, idx| {
        if (!std.mem.eql(u8, candidate.lexeme, token.lexeme)) continue;
        if (!isDefinitionHead(tokens, idx)) continue;
        return .{
            .uri = uri,
            .range = tokenRange(candidate),
        };
    }

    return null;
}

pub fn findDefinitionWithWorkspace(
    allocator: std.mem.Allocator,
    uri: []const u8,
    source: []const u8,
    position: protocol.Position,
    workspace_symbols: []const workspace.WorkspaceSymbol,
) !?protocol.Location {
    if (try findDefinition(allocator, uri, source, position)) |location| return location;

    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const token_idx = tokenAtPosition(tokens, position) orelse return null;
    const token = tokens[token_idx];
    if (token.kind != .ident) return null;
    if (isKeyword(token.lexeme) or isFieldName(token.lexeme)) return null;

    for (workspace_symbols) |symbol| {
        if (!std.mem.eql(u8, symbol.name, token.lexeme)) continue;
        return .{
            .uri = symbol.uri,
            .range = symbol.range,
        };
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

fn isDefinitionHead(tokens: []const lexer.Token, idx: usize) bool {
    if (braceDepthBefore(tokens, idx) != 0) return false;
    return isFunctionHead(tokens, idx) or isTypeDecl(tokens, idx);
}

fn isFunctionHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    const token = tokens[idx];
    const next = tokens[idx + 1];
    if (token.kind != .ident) return false;
    if (token.col != 1) return false;
    if (isKeyword(token.lexeme) or isFieldName(token.lexeme)) return false;
    if (token.line != next.line) return false;
    return next.kind == .symbol and std.mem.eql(u8, next.lexeme, "(");
}

fn isTypeDecl(tokens: []const lexer.Token, idx: usize) bool {
    if (tokens[idx].kind != .ident or !isTypeName(tokens[idx].lexeme)) return false;
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

fn tokenRange(token: lexer.Token) protocol.Range {
    const line = if (token.line == 0) 0 else token.line - 1;
    const start = if (token.col == 0) 0 else token.col - 1;
    return .{
        .start = .{ .line = line, .character = start },
        .end = .{ .line = line, .character = start + token.lexeme.len },
    };
}

fn isTypeName(name: []const u8) bool {
    return name.len > 0 and std.ascii.isUpper(name[0]);
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

test "findDefinition resolves current file function call" {
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

    const location = (try findDefinition(std.testing.allocator, "file:///tmp/app.do", source, .{ .line = 9, .character = 18 })).?;

    try std.testing.expectEqualStrings("file:///tmp/app.do", location.uri);
    try std.testing.expectEqual(@as(usize, 4), location.range.start.line);
    try std.testing.expectEqual(@as(usize, 0), location.range.start.character);
    try std.testing.expectEqual(@as(usize, 4), location.range.end.line);
    try std.testing.expectEqual(@as(usize, 9), location.range.end.character);
}

test "findDefinition resolves current file type reference" {
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

    const location = (try findDefinition(std.testing.allocator, "file:///tmp/app.do", source, .{ .line = 4, .character = 15 })).?;

    try std.testing.expectEqual(@as(usize, 0), location.range.start.line);
    try std.testing.expectEqual(@as(usize, 0), location.range.start.character);
    try std.testing.expectEqual(@as(usize, 0), location.range.end.line);
    try std.testing.expectEqual(@as(usize, 4), location.range.end.character);
}

test "findDefinition returns null for unknown token" {
    const source =
        \\User {
        \\    title text
        \\}
        \\
    ;

    const location = try findDefinition(std.testing.allocator, "file:///tmp/app.do", source, .{ .line = 1, .character = 4 });

    try std.testing.expect(location == null);
}

test "findDefinitionWithWorkspace resolves workspace type reference" {
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

    const location = (try findDefinitionWithWorkspace(
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
