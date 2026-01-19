const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodegenWat = @import("codegen_wat.zig").CodegenWat;
const token_mod = @import("token.zig");
const ast = @import("ast.zig");

test "codegen: end-to-end path get" {
    const allocator = std.testing.allocator;
    
    // 1. 预定义 User 类型 (模拟 Sema 已分析过的状态)
    const source = "get(user, .age)";
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

    // 手动注入 User 类型布局到 Sema (模拟 analyzeStructDef 的结果)
    var type_info = try allocator.create(@import("sema.zig").TypeInfo);
    type_info.* = .{
        .name = "User",
        .total_size = 16,
        .fields = std.StringHashMap(@import("sema.zig").FieldInfo).init(allocator),
    };
    try type_info.fields.put("age", .{ .name = "age", .offset = 12, .size = 1 });
    try s.type_registry.put("User", type_info);

    // 2. 执行 Codegen
    var cg = CodegenWat.init(allocator, &p.tree, &s);
    defer cg.deinit();

    try cg.genPathGet(node.data.path_op.target, node.data.path_op.path);

    // 3. 验证结果
    const output = cg.output.items;
    // 检查是否正确引用了从 Sema 算出的偏移量 12
    try std.testing.expect(std.mem.indexOf(u8, output, "i32.load offset=12") != null);
}
