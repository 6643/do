const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodegenWat = @import("codegen_wat.zig").CodegenWat;
const token_mod = @import("token.zig");
const ast = @import("ast.zig");

test "codegen: end-to-end path set" {
    const allocator = std.testing.allocator;
    
    // 1. 解析代码
    const source = "set(user, { [.age]: 21 })";
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

    var s = try Sema.init(allocator, &p.tree);
    defer s.deinit();

    // 注入 User 类型: age 偏移量 12
    var type_info = try allocator.create(@import("sema.zig").TypeInfo);
    type_info.* = .{
        .name = "User",
        .total_size = 16,
        .fields = std.StringHashMap(@import("sema.zig").FieldInfo).init(allocator),
    };
    try type_info.fields.put("age", .{ .name = "age", .offset = 12, .size = 1 });
    try s.type_registry.put("User", type_info);

    // 2. 生成代码
    var cg = CodegenWat.init(allocator, &p.tree, &s);
    defer cg.deinit();

    try cg.genPathSet(node.data.path_op.target, node.data.path_op.path);

    // 3. 验证 WAT 关键内容
    const output = cg.output.items;
    
    // 验证是否包含 RC 检查 (i32.load offset=0)
    try std.testing.expect(std.mem.indexOf(u8, output, "i32.load offset=0") != null);
    // 验证是否包含原地修改指令 (i32.store offset=12)
    try std.testing.expect(std.mem.indexOf(u8, output, "i32.store offset=12") != null);
    // 验证是否包含拷贝逻辑
    try std.testing.expect(std.mem.indexOf(u8, output, "call $copy_User") != null);
}
