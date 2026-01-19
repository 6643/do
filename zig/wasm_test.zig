const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodegenWasm = @import("codegen_wasm.zig").CodegenWasm;
const token_mod = @import("token.zig");

test "compiler: binary wasm generation" {
    const allocator = std.testing.allocator;
    const source = "main() { 42 }";
    
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

    var cg = CodegenWasm.init(allocator, &p.tree, &s);
    defer cg.deinit();
    const wasm = try cg.generate(root_idx);
    defer allocator.free(wasm);

    // 验证 WASM 魔数
    try std.testing.expect(std.mem.eql(u8, &[_]u8{ 0x00, 0x61, 0x73, 0x6d }, wasm[0..4]));
    // 验证版本号
    try std.testing.expect(std.mem.eql(u8, &[_]u8{ 0x01, 0x00, 0x00, 0x00 }, wasm[4..8]));

    std.debug.print("\n[Codegen] 生成了 {d} 字节的 WASM 二进制文件。\n", .{wasm.len});
    
    // 如果你想保存这个文件进行测试，可以打开下面的注释：
    // try std.fs.cwd().writeFile("test.wasm", wasm);
}
