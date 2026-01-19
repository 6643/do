const std = @import("std");
const ast = @import("ast.zig");
const Sema = @import("sema.zig").Sema;

test "sema: struct layout calculation" {
    const allocator = std.testing.allocator;
    var tree = ast.Tree.init("", &[_]@import("token.zig").Token{});
    defer tree.deinit(allocator);
    
    // 1. 构建 field_def: id u32
    const f1 = try tree.addNode(allocator, .{
        .tag = .field_def,
        .main_token = 0,
        .data = .{ .field_def = .{ .name = "id", .type_name = "u32", .attr = .{} } },
    });

    // 2. 构建 field_def: .age u8
    const f2 = try tree.addNode(allocator, .{
        .tag = .field_def,
        .main_token = 0,
        .data = .{ .field_def = .{ .name = "age", .type_name = "u8", .attr = .{ .is_private = true } } },
    });

    // 3. 构建 struct_def: User
    const fields = try allocator.dupe(ast.NodeIndex, &[_]ast.NodeIndex{ f1, f2 });
    defer allocator.free(fields);
    
    const s_idx = try tree.addNode(allocator, .{
        .tag = .struct_def,
        .main_token = 0,
        .data = .{ .struct_def = .{ .name = "User", .fields = fields } },
    });

    var s = try Sema.init(allocator, &tree);
    defer s.deinit();

    try s.analyze(s_idx);

    // 验证布局
    const user_info = s.type_registry.get("User").?;
    
    // id 的偏移量应该是 8 (预留 8B Meta)
    const id_field = user_info.fields.get("id").?;
    try std.testing.expectEqual(@as(u32, 8), id_field.offset);
    
    // age 的偏移量应该是 12 (8B Meta + 4B id)
    const age_field = user_info.fields.get("age").?;
    try std.testing.expectEqual(@as(u32, 12), age_field.offset);
    
    // 总大小应该是 16 (12 + 1B + 3B padding)
    try std.testing.expectEqual(@as(u32, 16), user_info.total_size);
}