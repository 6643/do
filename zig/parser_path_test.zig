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

test "parser: path get" {
    const allocator = std.testing.allocator;
    const source = "get(user, .name, 0)";
    const p = try parseString(allocator, source);
    defer {
        allocator.free(p.tokens);
        p.deinit();
        allocator.destroy(p);
    }

    const root_idx = try p.parse();
    const node = p.tree.nodes.items[root_idx];
    
    try std.testing.expectEqual(ast.NodeTag.path_get, node.tag);
    try std.testing.expectEqual(@as(usize, 2), node.data.path_op.path.len); // .name, 0
}

test "parser: path set batch" {
    const allocator = std.testing.allocator;
    const source = "set(user, { [.age]: 21, [.books, 0]: 100 })";
    const p = try parseString(allocator, source);
    defer {
        allocator.free(p.tokens);
        p.deinit();
        allocator.destroy(p);
    }

    const root_idx = try p.parse();
    const node = p.tree.nodes.items[root_idx];
    
    try std.testing.expectEqual(ast.NodeTag.path_set, node.tag);
    try std.testing.expectEqual(@as(usize, 2), node.data.path_op.path.len); // 两个 entry
    
    // 检查第一个 entry
    const entry_idx = node.data.path_op.path[0];
    const entry = p.tree.nodes.items[entry_idx];
    try std.testing.expectEqual(ast.NodeTag.set_entry, entry.tag);
    
    const path_seq_idx = entry.data.binary.lhs;
    try std.testing.expectEqual(ast.NodeTag.path_sequence, p.tree.nodes.items[path_seq_idx].tag);
}
