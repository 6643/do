const std = @import("std");
const lexer = @import("../build/lexer.zig");
const protocol = @import("protocol.zig");
const workspace = @import("workspace.zig");

pub fn collectCompletionItems(
    allocator: std.mem.Allocator,
    source: []const u8,
    position: protocol.Position,
) ![]protocol.CompletionItem {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var items = try std.ArrayList(protocol.CompletionItem).initCapacity(allocator, 0);
    errdefer items.deinit(allocator);

    var depth: usize = 0;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const token = tokens[idx];
        if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "{")) {
            depth += 1;
            continue;
        }
        if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or token.kind != .ident) continue;
        if (isKeyword(token.lexeme) or isFieldName(token.lexeme)) continue;

        if (isFunctionHead(tokens, idx)) {
            try appendUnique(allocator, &items, .{
                .label = token.lexeme,
                .kind = .function,
                .detail = signatureHead(source, token.line),
            });
            continue;
        }
        if (isTypeDecl(tokens, idx)) {
            try appendUnique(allocator, &items, .{
                .label = token.lexeme,
                .kind = .type_name,
                .detail = declarationHead(source, token.line),
            });
        }
    }

    if (isFieldSegmentPosition(source, position)) {
        try appendStructFields(allocator, &items, tokens);
    }

    return items.toOwnedSlice(allocator);
}

pub fn collectCompletionItemsWithWorkspace(
    allocator: std.mem.Allocator,
    source: []const u8,
    position: protocol.Position,
    workspace_symbols: []const workspace.WorkspaceSymbol,
) ![]protocol.CompletionItem {
    const local_items = try collectCompletionItems(allocator, source, position);
    var items = std.ArrayList(protocol.CompletionItem).fromOwnedSlice(local_items);
    errdefer items.deinit(allocator);

    for (workspace_symbols) |symbol| {
        try appendUnique(allocator, &items, .{
            .label = symbol.name,
            .kind = switch (symbol.kind) {
                .function => .function,
                .type_name => .type_name,
            },
            .detail = symbol.detail,
        });
    }

    return items.toOwnedSlice(allocator);
}

fn appendUnique(
    allocator: std.mem.Allocator,
    items: *std.ArrayList(protocol.CompletionItem),
    item: protocol.CompletionItem,
) !void {
    for (items.items) |existing| {
        if (std.mem.eql(u8, existing.label, item.label)) return;
    }
    try items.append(allocator, item);
}

fn isFunctionHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    const token = tokens[idx];
    const next = tokens[idx + 1];
    if (token.col != 1) return false;
    if (token.line != next.line) return false;
    return next.kind == .symbol and std.mem.eql(u8, next.lexeme, "(");
}

fn isTypeDecl(tokens: []const lexer.Token, idx: usize) bool {
    if (!isTypeName(tokens[idx].lexeme)) return false;
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

fn appendStructFields(
    allocator: std.mem.Allocator,
    items: *std.ArrayList(protocol.CompletionItem),
    tokens: []const lexer.Token,
) !void {
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        if (!isStructDecl(tokens, idx)) continue;

        idx += 2;
        var depth: usize = 1;
        while (idx < tokens.len) : (idx += 1) {
            const token = tokens[idx];
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "{")) {
                depth += 1;
                continue;
            }
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "}")) {
                depth -= 1;
                if (depth == 0) break;
                continue;
            }
            if (depth != 1 or token.kind != .ident) continue;
            if (isKeyword(token.lexeme) or isFieldName(token.lexeme)) continue;
            if (!isStructField(tokens, idx)) continue;
            try appendUnique(allocator, items, .{
                .label = token.lexeme,
                .kind = .field,
            });
        }
    }
}

fn isStructDecl(tokens: []const lexer.Token, idx: usize) bool {
    if (!isTypeName(tokens[idx].lexeme)) return false;
    if (idx + 1 >= tokens.len) return false;
    const next = tokens[idx + 1];
    if (tokens[idx].line != next.line) return false;
    return next.kind == .symbol and std.mem.eql(u8, next.lexeme, "{");
}

fn isStructField(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    const next = tokens[idx + 1];
    if (tokens[idx].line != next.line) return false;
    return next.kind == .ident and !isKeyword(next.lexeme);
}

fn isFieldSegmentPosition(source: []const u8, position: protocol.Position) bool {
    const line = zeroBasedLineSlice(source, position.line) orelse return false;
    const end = @min(position.character, line.len);
    if (end == 0) return false;
    if (line[end - 1] == '.') return true;

    var start = end;
    while (start > 0 and isIdentChar(line[start - 1])) {
        start -= 1;
    }
    return start > 0 and line[start - 1] == '.';
}

fn zeroBasedLineSlice(source: []const u8, zero_based_line: usize) ?[]const u8 {
    var line: usize = 0;
    var start: usize = 0;
    for (source, 0..) |ch, idx| {
        if (line == zero_based_line and ch == '\n') return source[start..idx];
        if (ch == '\n') {
            line += 1;
            start = idx + 1;
        }
    }

    if (line == zero_based_line) return source[start..];
    return null;
}

fn isIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

fn signatureHead(source: []const u8, one_based_line: usize) ?[]const u8 {
    const line = lineSlice(source, one_based_line) orelse return null;
    const body_start = if (std.mem.indexOf(u8, line, "{")) |idx|
        idx
    else if (std.mem.indexOf(u8, line, "=>")) |idx|
        idx
    else
        line.len;
    return std.mem.trim(u8, line[0..body_start], " \t\r\n");
}

fn declarationHead(source: []const u8, one_based_line: usize) ?[]const u8 {
    const line = lineSlice(source, one_based_line) orelse return null;
    return std.mem.trim(u8, line, " \t\r\n");
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

test "collectCompletionItems returns current file functions and types" {
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

    const items = try collectCompletionItems(std.testing.allocator, source, .{ .line = 5, .character = 4 });
    defer std.testing.allocator.free(items);

    try expectCompletion(items, "User", .type_name);
    try expectCompletion(items, "get_title", .function);
}

test "collectCompletionItems excludes field names from current file symbols" {
    const source =
        \\User {
        \\    title text
        \\}
        \\
    ;

    const items = try collectCompletionItems(std.testing.allocator, source, .{ .line = 1, .character = 4 });
    defer std.testing.allocator.free(items);

    try expectNoCompletion(items, "title");
}

test "collectCompletionItems adds struct fields in field segment context" {
    const source =
        \\User {
        \\    title text
        \\    age i32
        \\}
        \\
        \\get_title(user User) -> text {
        \\    return @get(user, .)
        \\}
        \\
    ;

    const items = try collectCompletionItems(std.testing.allocator, source, .{ .line = 6, .character = 23 });
    defer std.testing.allocator.free(items);

    try expectCompletion(items, "title", .field);
    try expectCompletion(items, "age", .field);
}

test "collectCompletionItemsWithWorkspace appends workspace functions and types" {
    const source =
        \\test "use" {
        \\    return
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
        .{
            .name = "load_user",
            .kind = .function,
            .uri = "file:///tmp/project/user.do",
            .range = .{ .start = .{ .line = 4, .character = 0 }, .end = .{ .line = 4, .character = 9 } },
            .detail = "load_user() -> ProjectUser",
        },
    };

    const items = try collectCompletionItemsWithWorkspace(std.testing.allocator, source, .{ .line = 1, .character = 4 }, &workspace_symbols);
    defer std.testing.allocator.free(items);

    try expectCompletion(items, "ProjectUser", .type_name);
    try expectCompletion(items, "load_user", .function);
}

fn expectCompletion(items: []const protocol.CompletionItem, label: []const u8, kind: protocol.CompletionItemKind) !void {
    for (items) |item| {
        if (!std.mem.eql(u8, item.label, label)) continue;
        try std.testing.expectEqual(kind, item.kind);
        return;
    }
    return error.MissingCompletionItem;
}

fn expectNoCompletion(items: []const protocol.CompletionItem, label: []const u8) !void {
    for (items) |item| {
        if (std.mem.eql(u8, item.label, label)) return error.UnexpectedCompletionItem;
    }
}
