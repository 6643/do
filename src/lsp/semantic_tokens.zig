const std = @import("std");
const lexer = @import("../build/lexer.zig");
const source_helpers = @import("source_helpers.zig");
const is_field_name = source_helpers.is_field_name;
const is_keyword = source_helpers.is_keyword;


pub const legendTokenTypes = [_][]const u8{
    "keyword",
    "type",
    "function",
    "parameter",
    "variable",
    "field",
    "property",
    "string",
    "number",
    "comment",
    "operator",
    "builtin",
};

pub const legendTokenModifiers = [_][]const u8{};

pub const SemanticTokenKind = enum {
    keyword,
    type_name,
    function,
    parameter,
    variable,
    field,
    property,
    string,
    number,
    comment,
    operator,
    builtin,
};

pub const SemanticToken = struct {
    line: u32,
    start: u32,
    length: u32,
    token_type: SemanticTokenKind,
    modifiers: u32 = 0,
};

pub fn encode_semantic_tokens(allocator: std.mem.Allocator, tokens: []const SemanticToken) ![]u32 {
    var data = try std.ArrayList(u32).initCapacity(allocator, tokens.len * 5);
    errdefer data.deinit(allocator);

    var prev_line: u32 = 0;
    var prev_start: u32 = 0;
    for (tokens, 0..) |token, idx| {
        const delta_line = if (idx == 0) token.line else token.line - prev_line;
        const delta_start = if (idx == 0 or delta_line != 0) token.start else token.start - prev_start;

        try data.append(allocator, delta_line);
        try data.append(allocator, delta_start);
        try data.append(allocator, token.length);
        try data.append(allocator, token_type_index(token.token_type));
        try data.append(allocator, token.modifiers);

        prev_line = token.line;
        prev_start = token.start;
    }

    return data.toOwnedSlice(allocator);
}

pub fn collect_semantic_tokens(allocator: std.mem.Allocator, source: []const u8) ![]SemanticToken {
    const raw_tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(raw_tokens);

    var out = try std.ArrayList(SemanticToken).initCapacity(allocator, raw_tokens.len);
    errdefer out.deinit(allocator);

    var idx: usize = 0;
    while (idx < raw_tokens.len) : (idx += 1) {
        const token = raw_tokens[idx];
        if (is_builtin_head(raw_tokens, idx)) {
            const name = raw_tokens[idx + 1];
            try out.append(allocator, .{
                .line = @as(u32, @intCast(token.line - 1)),
                .start = @as(u32, @intCast(token.col - 1)),
                .length = @as(u32, @intCast(token.lexeme.len + name.lexeme.len)),
                .token_type = .builtin,
            });
            idx += 1;
            continue;
        }

        const kind = classify_lexer_token(raw_tokens, idx);
        try out.append(allocator, .{
            .line = @as(u32, @intCast(token.line - 1)),
            .start = @as(u32, @intCast(token.col - 1)),
            .length = @as(u32, @intCast(token.lexeme.len)),
            .token_type = kind,
        });
    }

    return out.toOwnedSlice(allocator);
}

fn token_type_index(kind: SemanticTokenKind) u32 {
    return switch (kind) {
        .keyword => 0,
        .type_name => 1,
        .function => 2,
        .parameter => 3,
        .variable => 4,
        .field => 5,
        .property => 6,
        .string => 7,
        .number => 8,
        .comment => 9,
        .operator => 10,
        .builtin => 11,
    };
}

fn classify_lexer_token(tokens: []const lexer.Token, idx: usize) SemanticTokenKind {
    const token = tokens[idx];
    return switch (token.kind) {
        .ident => classify_ident_token(tokens, idx),
        .number => .number,
        .string => .string,
        .symbol => .operator,
    };
}

fn classify_ident_token(tokens: []const lexer.Token, idx: usize) SemanticTokenKind {
    const token = tokens[idx];
    if (is_keyword(token.lexeme)) return .keyword;
    if (is_field_name(token.lexeme)) return .field;
    if (is_type_name(token.lexeme)) return .type_name;
    if (is_function_head(tokens, idx)) return .function;
    return .variable;
}

fn is_builtin_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    const at = tokens[idx];
    const name = tokens[idx + 1];
    if (at.kind != .symbol or !std.mem.eql(u8, at.lexeme, "@")) return false;
    if (name.kind != .ident) return false;
    if (at.line != name.line) return false;
    return at.col + at.lexeme.len == name.col;
}

fn is_type_name(name: []const u8) bool {
    if (name.len == 0) return false;
    if (std.ascii.isUpper(name[0])) return true;
    return is_builtin_type_name(name);
}

fn is_builtin_type_name(name: []const u8) bool {
    const names = [_][]const u8{
        "bool",
        "text",
        "u8",
        "u16",
        "u32",
        "u64",
        "usize",
        "isize",
        "i8",
        "i16",
        "i32",
        "i64",
        "f32",
        "f64",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn is_function_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].line != tokens[idx + 1].line) return false;
    return tokens[idx + 1].kind == .symbol and std.mem.eql(u8, tokens[idx + 1].lexeme, "(");
}

test "semantic token legend order is stable" {
    try std.testing.expectEqual(@as(usize, 12), legendTokenTypes.len);
    try std.testing.expectEqualStrings("keyword", legendTokenTypes[0]);
    try std.testing.expectEqualStrings("type", legendTokenTypes[1]);
    try std.testing.expectEqualStrings("function", legendTokenTypes[2]);
    try std.testing.expectEqualStrings("builtin", legendTokenTypes[11]);
    try std.testing.expectEqual(@as(usize, 0), legendTokenModifiers.len);
}

test "encode_semantic_tokens returns LSP delta encoded five-tuples" {
    const tokens = [_]SemanticToken{
        .{ .line = 0, .start = 0, .length = 4, .token_type = .keyword },
        .{ .line = 0, .start = 5, .length = 4, .token_type = .function },
        .{ .line = 2, .start = 4, .length = 2, .token_type = .variable },
        .{ .line = 2, .start = 10, .length = 1, .token_type = .number },
    };

    const encoded = try encode_semantic_tokens(std.testing.allocator, &tokens);
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqualSlices(u32, &.{
        0, 0, 4, 0, 0,
        0, 5, 4, 2, 0,
        2, 4, 2, 4, 0,
        0, 6, 1, 8, 0,
    }, encoded);
}

test "collect_semantic_tokens classifies lexer tokens" {
    const tokens = try collect_semantic_tokens(std.testing.allocator,
        \\if true {
        \\    value = 42
        \\}
        \\
    );
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 7), tokens.len);

    try std.testing.expectEqual(SemanticToken{ .line = 0, .start = 0, .length = 2, .token_type = .keyword }, tokens[0]);
    try std.testing.expectEqual(SemanticToken{ .line = 0, .start = 3, .length = 4, .token_type = .keyword }, tokens[1]);
    try std.testing.expectEqual(SemanticToken{ .line = 0, .start = 8, .length = 1, .token_type = .operator }, tokens[2]);
    try std.testing.expectEqual(SemanticToken{ .line = 1, .start = 4, .length = 5, .token_type = .variable }, tokens[3]);
    try std.testing.expectEqual(SemanticToken{ .line = 1, .start = 10, .length = 1, .token_type = .operator }, tokens[4]);
    try std.testing.expectEqual(SemanticToken{ .line = 1, .start = 12, .length = 2, .token_type = .number }, tokens[5]);
    try std.testing.expectEqual(SemanticToken{ .line = 2, .start = 0, .length = 1, .token_type = .operator }, tokens[6]);
}

test "collect_semantic_tokens applies minimal semantic classifications" {
    const tokens = try collect_semantic_tokens(std.testing.allocator,
        \\User {
        \\    title text
        \\}
        \\get_title(user User) -> text {
        \\    return @get(user, .title)
        \\}
        \\
    );
    defer std.testing.allocator.free(tokens);

    try expect_has_semantic_token(tokens, .{ .line = 0, .start = 0, .length = 4, .token_type = .type_name });
    try expect_has_semantic_token(tokens, .{ .line = 1, .start = 10, .length = 4, .token_type = .type_name });
    try expect_has_semantic_token(tokens, .{ .line = 3, .start = 0, .length = 9, .token_type = .function });
    try expect_has_semantic_token(tokens, .{ .line = 3, .start = 15, .length = 4, .token_type = .type_name });
    try expect_has_semantic_token(tokens, .{ .line = 3, .start = 24, .length = 4, .token_type = .type_name });
    try expect_has_semantic_token(tokens, .{ .line = 4, .start = 11, .length = 4, .token_type = .builtin });
    try expect_has_semantic_token(tokens, .{ .line = 4, .start = 22, .length = 6, .token_type = .field });
}

fn expect_has_semantic_token(tokens: []const SemanticToken, expected: SemanticToken) !void {
    for (tokens) |token| {
        if (std.meta.eql(token, expected)) return;
    }
    return error.MissingSemanticToken;
}
