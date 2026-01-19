const std = @import("std");
const runtime = @import("runtime.zig");

test "runtime: slab bitmap allocation" {
    const allocator = std.testing.allocator;

    // 分配 8KB 内存，并在其中找到一个 4KB 且 8 字节对齐的块
    const raw_mem = try allocator.alloc(u8, 8192);
    defer allocator.free(raw_mem);

    const start_addr = @intFromPtr(raw_mem.ptr);
    const page_ptr = (start_addr + 4095) & ~@as(usize, 4095);

    // 清理该页面内存
    const page_slice = @as([*]u8, @ptrFromInt(page_ptr))[0..4096];
    @memset(page_slice, 0);

    var rt = runtime.Runtime.init(0);

    const header = @as(*runtime.PageHeader, @ptrFromInt(page_ptr));
    header.free_cnt = 64;
    header.type_id = 1;

    const slot_size = 32;

    const obj1 = rt.alloc_in_page(page_ptr, slot_size).?;
    try std.testing.expectEqual(header.free_cnt, 63);
    try std.testing.expectEqual(header.get_bitmap().*, 1);

    // 检查 Slot Header 初始状态
    const slot1 = @as(*runtime.SlotHeader, @ptrFromInt(obj1));
    try std.testing.expectEqual(slot1.rc, 1);
    try std.testing.expectEqual(slot1.type_id, 1);

    _ = rt.alloc_in_page(page_ptr, slot_size).?;
    try std.testing.expectEqual(header.free_cnt, 62);
    try std.testing.expectEqual(header.get_bitmap().*, 3);

    rt.free_in_page(page_ptr, obj1, slot_size);
    try std.testing.expectEqual(header.free_cnt, 63);
    try std.testing.expectEqual(header.get_bitmap().*, 2);

    const obj1_new = rt.alloc_in_page(page_ptr, slot_size).?;
    try std.testing.expectEqual(obj1, obj1_new);
    try std.testing.expectEqual(header.get_bitmap().*, 3);
}

test "runtime: rc management" {
    var rt = runtime.Runtime.init(0);

    // 模拟一个对象
    var raw_slot: [32]u8 align(8) = undefined;
    const obj_ptr = @intFromPtr(&raw_slot);
    const slot = @as(*runtime.SlotHeader, @ptrCast(&raw_slot));
    slot.rc = 1;
    slot.type_id = 10;

    try std.testing.expect(rt.is_unique(obj_ptr));

    rt.inc_rc(obj_ptr);
    try std.testing.expectEqual(slot.rc, 2);
    try std.testing.expect(!rt.is_unique(obj_ptr));

    const remaining = rt.dec_rc(obj_ptr);
    try std.testing.expectEqual(remaining, 1);
    try std.testing.expectEqual(slot.rc, 1);
    try std.testing.expect(rt.is_unique(obj_ptr));
}
