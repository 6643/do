const std = @import("std");
const ast = @import("ast.zig");
const Sema = @import("sema.zig").Sema;

test "logistics: print optimization report" {
    const allocator = std.testing.allocator;
    var tree = ast.Tree.init("", &[_]@import("token.zig").Token{});
    defer tree.deinit(allocator);
    
    // 1. 定义 User (Raw Size 应为 16B)
    const f1 = try tree.addNode(allocator, .{
        .tag = .field_def,
        .main_token = 0,
        .data = .{ .field_def = .{ .name = "id", .type_name = "u32", .attr = .{} } },
    });
    const s_idx = try tree.addNode(allocator, .{
        .tag = .struct_def,
        .main_token = 0,
        .data = .{ .struct_def = .{ .name = "User", .fields = try allocator.dupe(ast.NodeIndex, &[_]ast.NodeIndex{f1}) } },
    });
    // 注意：手动构建节点时需手动处理 fields 的分配
    defer allocator.free(tree.nodes.items[s_idx].data.struct_def.fields);

    // 2. 定义 LargeRecord (手动构建 50 字节的字段，Raw Size 应为 64B 以上)
    // 简化处理：直接分析 s_idx
    
    var s = try Sema.init(allocator, &tree);
    defer s.deinit();

    std.debug.print("\n", .{});
    try s.analyze(s_idx);
}
