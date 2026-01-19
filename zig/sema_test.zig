const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const token_mod = @import("token.zig");

fn runSemaOn(allocator: std.mem.Allocator, source: [:0]const u8) !void {
    var lexer = Lexer.init(source);
    var tokens = std.ArrayListUnmanaged(token_mod.Token){};
    defer tokens.deinit(allocator);
    while (true) {
        const tok = lexer.next();
        try tokens.append(allocator, tok);
        if (tok.tag == .eof) break;
    }

    var p = Parser.init(allocator, source, try allocator.dupe(token_mod.Token, tokens.items));
    defer {
        allocator.free(p.tokens);
        p.deinit();
    }

    const root_idx = try p.parse();
    var s = try Sema.init(allocator, &p.tree);
    defer s.deinit();

    try s.analyze(root_idx);
}

test "sema: immutable check" {
    const allocator = std.testing.allocator;

    // 合法：定义不可变变量
    try runSemaOn(allocator, "_Pi := 3.14");

    // 不合法：修改不可变变量
    const source = "_Pi := 3.14, _Pi = 3";
    const result = runSemaOn(allocator, source);
    try std.testing.expectError(error.ImmutableVariableModified, result);
}

test "sema: undefined variable" {
    const allocator = std.testing.allocator;
    const source = "a = 1 + b";
    const result = runSemaOn(allocator, source);
    try std.testing.expectError(error.UndefinedVariable, result);
}

test "sema: perceus last use marking" {
    const allocator = std.testing.allocator;
    const source = "a := 10, b := a + a"; // 使用逗号分隔

    var lexer = Lexer.init(source);
    var tokens = std.ArrayListUnmanaged(token_mod.Token){};
    defer tokens.deinit(allocator);
    while (true) {
        const tok = lexer.next();
        try tokens.append(allocator, tok);
        if (tok.tag == .eof) break;
    }

    var p = Parser.init(allocator, source, try allocator.dupe(token_mod.Token, tokens.items));
    defer {
        allocator.free(p.tokens);
        p.deinit();
    }

    const root_idx = try p.parse();
    var s = try Sema.init(allocator, &p.tree);
    defer s.deinit();

    try s.analyze(root_idx);

    var a_uses: usize = 0;
    for (p.tree.nodes.items) |node| {
        if (node.tag == .identifier and std.mem.eql(u8, node.data.identifier.name, "a")) {
            a_uses += 1;
            if (a_uses == 1) {
                // 定义点
            } else if (a_uses == 2) {
                // 第一个引用
                try std.testing.expectEqual(false, node.is_last_use);
            } else if (a_uses == 3) {
                // 第二个引用 (最后一个)
                try std.testing.expectEqual(true, node.is_last_use);
            }
        }
    }
}
