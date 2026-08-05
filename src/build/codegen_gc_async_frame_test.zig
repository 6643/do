const std = @import("std");
const async_byte_budget = @import("async_byte_budget.zig");
const async_model = @import("codegen_async_model.zig");
const gc_async_frame = @import("codegen_gc_async_frame.zig");

test "task frame admission accounts layout bytes and releases exactly once" {
    const slots = [_]async_model.FrameLayoutSlot{};
    const layout = async_model.FrameLayout{ .size = 24, .slots = &slots };
    const frame_bytes = try gc_async_frame.bytes_for_frame_layout(layout);

    var budget = async_byte_budget.ByteBudget.init(frame_bytes);
    var pool = gc_async_frame.TaskFramePool.init(&budget, frame_bytes);

    var allocation = try pool.acquire();
    try std.testing.expectEqual(frame_bytes, budget.committed_bytes());
    try std.testing.expectEqual(@as(u64, 1), pool.live_frames());
    try std.testing.expectError(error.ByteBudgetExceeded, pool.acquire());
    try std.testing.expectEqual(@as(u64, 1), pool.live_frames());

    try pool.release(&allocation);
    try std.testing.expectEqual(@as(u64, 0), budget.committed_bytes());
    try std.testing.expectEqual(@as(u64, 0), pool.live_frames());
    try std.testing.expectError(error.AllocationInvariantViolation, pool.release(&allocation));
}

test "task frame admission rejects a layout smaller than its fixed header" {
    const slots = [_]async_model.FrameLayoutSlot{};
    const layout = async_model.FrameLayout{ .size = 8, .slots = &slots };
    try std.testing.expectError(error.InvalidAsyncFrameLayout, gc_async_frame.bytes_for_frame_layout(layout));
}

test "frame table layout emits the accounted byte size" {
    const slots = [_]async_model.FrameLayoutSlot{};
    const layout = async_model.FrameLayout{ .size = 24, .slots = &slots };
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try gc_async_frame.emit_frame_table_layout(std.testing.allocator, &wat, layout);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, ";; [async-frame-bytes] 24") != null);
}

test "budgeted frame allocator accounts a layout before table growth" {
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try gc_async_frame.emit_frame_table_allocator_with_bytes(std.testing.allocator, &wat, 24);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, ";; [async-frame-budget-bytes] 24") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "call $async-byte-budget-reserve") != null);
    const frame_free = std.mem.indexOf(u8, wat.items, "(func $frame-free").?;
    const release = frame_free + std.mem.indexOf(u8, wat.items[frame_free..], "call $async-byte-budget-release").?;
    const clear = frame_free + std.mem.indexOf(u8, wat.items[frame_free..], "ref.null $async-frame").?;
    try std.testing.expect(release < clear);
}

test "budgeted frame allocator exposes an owner-configured runtime limit" {
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try gc_async_frame.emit_frame_table_allocator_with_bytes(std.testing.allocator, &wat, 24);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, ";; [async-byte-budget-limit] -1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "(global $async-byte-budget-limit (mut i64) (i64.const -1))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "(func $async-byte-budget-limit (export \"[async-config]byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "(func (export \"byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "global.get $async-byte-budget-limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "i64.gt_u") != null);
}
