const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const token_mod = @import("token.zig");
const ast = @import("ast.zig");

fn parseString(allocator: std.mem.Allocator, source: [:0]const u8) !*Parser {
    var lexer = Lexer.init(source);
    var tokens = std.ArrayListUnmanaged(token_mod.Token){};
    defer tokens.deinit(allocator);

    while (true) {
        const tok = lexer.next();
        try tokens.append(allocator, tok);
        if (tok.tag == .eof) break;
    }
    
    const p = try allocator.create(Parser);
    p.* = Parser.init(allocator, source, try allocator.dupe(token_mod.Token, tokens.items));
    return p;
}

test "parser: identifier attributes" {
    const allocator = std.testing.allocator;
    const source = "._Secret := 123";
    const p = try parseString(allocator, source);
    defer {
        allocator.free(p.tokens);
        p.deinit();
        allocator.destroy(p);
    }

    const root_idx = try p.parse();
    const node = p.tree.nodes.items[root_idx];
    
    try std.testing.expectEqual(ast.NodeTag.assign_init, node.tag);
    
    const lhs_idx = node.data.binary.lhs;
    const lhs = p.tree.nodes.items[lhs_idx];
    try std.testing.expect(lhs.data.identifier.attr.is_private);
    try std.testing.expect(lhs.data.identifier.attr.is_immutable);
}

test "parser: operator precedence" {
    const allocator = std.testing.allocator;
    const source = "1 + 2 * 3";
    const p = try parseString(allocator, source);
    defer {
        allocator.free(p.tokens);
        p.deinit();
        allocator.destroy(p);
    }

    const root_idx = try p.parse();
    const node = p.tree.nodes.items[root_idx];
    
    try std.testing.expectEqual(ast.NodeTag.binary_op, node.tag);
    
    const rhs_idx = node.data.binary.rhs;
    const rhs = p.tree.nodes.items[rhs_idx];
    try std.testing.expectEqual(ast.NodeTag.binary_op, rhs.tag);
}

test "parser: loop with label" {
    const allocator = std.testing.allocator;
    const source = "loop { #outer 123 }";
    const p = try parseString(allocator, source);
    defer {
        allocator.free(p.tokens);
        p.deinit();
        allocator.destroy(p);
    }

    const root_idx = try p.parse();
    const node = p.tree.nodes.items[root_idx];
    
    try std.testing.expectEqual(ast.NodeTag.loop_expr, node.tag);
    try std.testing.expect(node.data.loop_expr.label_token != 0);
    
    const label_tok = p.tree.tokens[node.data.loop_expr.label_token];
    const label_name = p.tree.source[label_tok.loc.start..label_tok.loc.end];
    try std.testing.expectEqualStrings("outer", label_name);
}
