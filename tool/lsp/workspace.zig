const std = @import("std");
const lexer = @import("../build/lexer.zig");
const protocol = @import("protocol.zig");

pub const WorkspaceSymbolKind = enum {
    function,
    type_name,
};

pub const WorkspaceSymbol = struct {
    name: []const u8,
    kind: WorkspaceSymbolKind,
    uri: []const u8,
    range: protocol.Range,
    detail: ?[]const u8 = null,
};

pub fn collectWorkspaceSymbols(
    io: std.Io,
    allocator: std.mem.Allocator,
    root_uris: []const []const u8,
) ![]WorkspaceSymbol {
    var symbols = try std.ArrayList(WorkspaceSymbol).initCapacity(allocator, 0);
    errdefer freeWorkspaceSymbolList(allocator, &symbols);

    for (root_uris) |root_uri| {
        const root_path = fileUriPath(root_uri) orelse continue;
        var dir = std.Io.Dir.openDirAbsolute(io, root_path, .{
            .iterate = true,
            .access_sub_paths = true,
        }) catch continue;
        defer dir.close(io);

        var iter = dir.iterate();
        while (try iter.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".do")) continue;

            const source = dir.readFileAlloc(io, entry.name, allocator, .limited(16 * 1024 * 1024)) catch continue;
            defer allocator.free(source);

            const file_uri = try joinFileUri(allocator, root_uri, entry.name);
            defer allocator.free(file_uri);
            try appendSourceSymbols(allocator, &symbols, file_uri, source);
        }
    }

    return symbols.toOwnedSlice(allocator);
}

pub fn freeWorkspaceSymbols(allocator: std.mem.Allocator, symbols: []WorkspaceSymbol) void {
    var list = std.ArrayList(WorkspaceSymbol).fromOwnedSlice(symbols);
    freeWorkspaceSymbolList(allocator, &list);
}

pub fn freeWorkspaceSymbolList(allocator: std.mem.Allocator, symbols: *std.ArrayList(WorkspaceSymbol)) void {
    for (symbols.items) |symbol| {
        allocator.free(symbol.name);
        allocator.free(symbol.uri);
        if (symbol.detail) |detail| allocator.free(detail);
    }
    symbols.deinit(allocator);
}

fn fileUriPath(uri: []const u8) ?[]const u8 {
    const prefix = "file://";
    if (!std.mem.startsWith(u8, uri, prefix)) return null;
    const path = uri[prefix.len..];
    if (!std.mem.startsWith(u8, path, "/")) return null;
    if (std.mem.indexOfScalar(u8, path, '%') != null) return null;
    return path;
}

fn joinFileUri(allocator: std.mem.Allocator, root_uri: []const u8, file_name: []const u8) ![]const u8 {
    if (std.mem.endsWith(u8, root_uri, "/")) {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_uri, file_name });
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ root_uri, file_name });
}

fn appendSourceSymbols(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayList(WorkspaceSymbol),
    uri: []const u8,
    source: []const u8,
) !void {
    const tokens = lexer.tokenize(allocator, source) catch return;
    defer allocator.free(tokens);

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
            try appendSymbol(allocator, symbols, uri, token, .function, signatureHead(source, token.line));
            continue;
        }
        if (isTypeDecl(tokens, idx)) {
            try appendSymbol(allocator, symbols, uri, token, .type_name, declarationHead(source, token.line));
        }
    }
}

fn appendSymbol(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayList(WorkspaceSymbol),
    uri: []const u8,
    token: lexer.Token,
    kind: WorkspaceSymbolKind,
    detail: ?[]const u8,
) !void {
    const owned_name = try allocator.dupe(u8, token.lexeme);
    errdefer allocator.free(owned_name);

    const owned_uri = try allocator.dupe(u8, uri);
    errdefer allocator.free(owned_uri);

    const owned_detail = if (detail) |value| try allocator.dupe(u8, value) else null;
    errdefer if (owned_detail) |value| allocator.free(value);

    try symbols.append(allocator, .{
        .name = owned_name,
        .kind = kind,
        .uri = owned_uri,
        .range = tokenRange(token),
        .detail = owned_detail,
    });
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

fn tokenRange(token: lexer.Token) protocol.Range {
    const line = if (token.line == 0) 0 else token.line - 1;
    const start = if (token.col == 0) 0 else token.col - 1;
    return .{
        .start = .{ .line = line, .character = start },
        .end = .{ .line = line, .character = start + token.lexeme.len },
    };
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

test "collectWorkspaceSymbols scans do files under file workspace root" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "user.do",
        .data =
        \\User {
        \\    title text
        \\}
        \\
        \\get_title(user User) -> text {
        \\    return @get(user, .title)
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "ignore.txt",
        .data =
        \\Ignored {
        \\}
        \\
        ,
    });

    const root_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root_path);
    const root_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}", .{root_path});
    defer std.testing.allocator.free(root_uri);

    const symbols = try collectWorkspaceSymbols(std.testing.io, std.testing.allocator, &.{root_uri});
    defer freeWorkspaceSymbols(std.testing.allocator, symbols);

    try expectWorkspaceSymbol(symbols, "User", .type_name, "file://", 0, 0);
    try expectWorkspaceSymbol(symbols, "get_title", .function, "file://", 4, 0);
    try expectNoWorkspaceSymbol(symbols, "Ignored");
}

fn expectWorkspaceSymbol(
    symbols: []const WorkspaceSymbol,
    name: []const u8,
    kind: WorkspaceSymbolKind,
    uri_prefix: []const u8,
    line: usize,
    character: usize,
) !void {
    for (symbols) |symbol| {
        if (!std.mem.eql(u8, symbol.name, name)) continue;
        try std.testing.expectEqual(kind, symbol.kind);
        try std.testing.expect(std.mem.startsWith(u8, symbol.uri, uri_prefix));
        try std.testing.expectEqual(line, symbol.range.start.line);
        try std.testing.expectEqual(character, symbol.range.start.character);
        return;
    }
    return error.MissingWorkspaceSymbol;
}

fn expectNoWorkspaceSymbol(symbols: []const WorkspaceSymbol, name: []const u8) !void {
    for (symbols) |symbol| {
        if (std.mem.eql(u8, symbol.name, name)) return error.UnexpectedWorkspaceSymbol;
    }
}
