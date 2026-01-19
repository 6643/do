const std = @import("std");
const Compiler = @import("do.zig").Compiler;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodegenWat = @import("codegen_wat.zig").CodegenWat;
const token_mod = @import("token.zig");

test "stdlib: built-in functions injection" {
    const allocator = std.testing.allocator;
    const source = "main() { 1 }";
    
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

    var cg = CodegenWat.init(allocator, &p.tree, &s);
    defer cg.deinit();
    const wat = try cg.generateModule(root_idx);

    // 验证标准库注入
    try std.testing.expect(std.mem.indexOf(u8, wat, "import \"env\" \"print\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "func $list_append") != null);
    // 验证 Perceus 逻辑是否存在 (检查 RC == 1 的指令)
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.eq") != null);
}
