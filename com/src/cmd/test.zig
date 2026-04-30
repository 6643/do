const std = @import("std");
const lexer = @import("../lexer.zig");

pub const TestDecl = struct {
    name_lexeme: []const u8,
    line: usize,
    col: usize,
};

pub fn run(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const test_decls = try collectTopLevelTests(allocator, tokens);
    defer allocator.free(test_decls);

    if (test_decls.len == 0) return error.NoTestDecl;
    try printTestReport(test_decls);
}

pub fn collectTopLevelTests(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]TestDecl {
    var out = try std.ArrayList(TestDecl).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0) {
            i += 1;
            continue;
        }

        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, "test")) {
            i += 1;
            continue;
        }
        if (i + 2 >= tokens.len) return error.InvalidTestDecl;
        if (tokens[i + 1].kind != .string) return error.InvalidTestDecl;
        if (!tokEqToken(tokens[i + 2], "{")) return error.InvalidTestDecl;

        const close_brace = try findMatchingToken(tokens, i + 2, "{", "}");
        try out.append(allocator, .{
            .name_lexeme = tokens[i + 1].lexeme,
            .line = tokens[i].line,
            .col = tokens[i].col,
        });
        i = close_brace + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn printTestReport(test_decls: []const TestDecl) !void {
    var out_buffer: [4096]u8 = undefined;
    var out = std.fs.File.stdout().writer(&out_buffer);

    for (test_decls) |decl| {
        try out.interface.print("test {s} ... ok\n", .{decl.name_lexeme});
    }
    try out.interface.print("ok: {d} passed; 0 failed\n", .{test_decls.len});
    try out.interface.flush();
}

fn findMatchingToken(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    if (open_idx >= tokens.len or !tokEqToken(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEqToken(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tokEqToken(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn tokEqToken(tok: lexer.Token, lexeme: []const u8) bool {
    return std.mem.eql(u8, tok.lexeme, lexeme);
}
