const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const CodegenWat = @import("codegen_wat.zig").CodegenWat;
const token_mod = @import("token.zig");

test "codegen: path set expansion" {
    const allocator = std.testing.allocator;
    const source = "set(user, { [.age]: 21, [.books, 0]: 100 })";
    
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
    const node = p.tree.nodes.items[root_idx];

    var cg = CodegenWat.init(allocator, &p.tree);
    defer cg.deinit();

    try cg.genPathSet(node.data.path_op.target, node.data.path_op.path);

    // 验证生成的 WAT 文本
    const output = cg.output.items;
    try std.testing.expect(std.mem.indexOf(u8, output, ".age") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".books") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "index") != null);
}
