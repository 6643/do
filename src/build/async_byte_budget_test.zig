const std = @import("std");
const budget = @import("async_byte_budget.zig");

test "reservation commit and release account bytes exactly once" {
    var bytes = budget.ByteBudget.init(100);
    var reservation = try bytes.reserve(40);
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectEqual(@as(u64, 40), bytes.reserved_bytes());

    var allocation = try reservation.commit();
    try std.testing.expectEqual(@as(u64, 40), bytes.committed_bytes());
    try std.testing.expectEqual(@as(u64, 0), bytes.reserved_bytes());
    try std.testing.expectError(error.ReservationAlreadyFinalized, reservation.rollback());

    try allocation.release();
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectError(error.AllocationAlreadyReleased, allocation.release());
}

test "rollback restores capacity and pending reservations count" {
    var bytes = budget.ByteBudget.init(64);
    var first = try bytes.reserve(48);
    var second = try bytes.reserve(16);
    try std.testing.expectError(error.ByteBudgetExceeded, bytes.reserve(1));
    try second.rollback();
    try std.testing.expectEqual(@as(u64, 48), bytes.reserved_bytes());
    var allocation = try first.commit();
    try std.testing.expectEqual(@as(u64, 48), bytes.committed_bytes());
    try allocation.release();
    try std.testing.expectEqual(@as(u64, 64), bytes.available_bytes());
}

test "reservation finalization rejects a second commit" {
    var bytes = budget.ByteBudget.init(32);
    var reservation = try bytes.reserve(8);
    var allocation = try reservation.commit();
    try std.testing.expectError(error.ReservationAlreadyFinalized, reservation.commit());
    try allocation.release();
}

test "failed reservation does not mutate in-flight accounting" {
    var bytes = budget.ByteBudget.init(std.math.maxInt(u64));
    var full = try bytes.reserve(std.math.maxInt(u64));
    try std.testing.expectError(error.ByteSizeOverflow, bytes.reserve(std.math.maxInt(u64)));
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectEqual(std.math.maxInt(u64), bytes.reserved_bytes());
    try full.rollback();
    try std.testing.expectEqual(std.math.maxInt(u64), bytes.available_bytes());
}

test "runtime budget owner rejects a limit below live usage" {
    var bytes = budget.ByteBudget.init(16);
    var reservation = try bytes.reserve(8);
    var allocation = try reservation.commit();

    try std.testing.expectError(error.ByteBudgetLimitBelowUsage, bytes.configure(4));
    try std.testing.expectEqual(@as(u64, 16), bytes.limit_bytes());
    try bytes.configure(24);
    try std.testing.expectEqual(@as(u64, 24), bytes.limit_bytes());

    var pending = try bytes.reserve(8);
    try std.testing.expectError(error.ByteBudgetLimitBelowUsage, bytes.configure(15));
    try pending.rollback();

    try allocation.release();
    try bytes.configure(4);
    try std.testing.expectEqual(@as(u64, 4), bytes.limit_bytes());
}

test "checked cost formulas cover runtime accounting points" {
    try std.testing.expectEqual(@as(u64, 28), try budget.bytes_for_task_frame(16, 12));
    try std.testing.expectEqual(@as(u64, 40), try budget.bytes_for_queue_slots(8, 5));
    try std.testing.expectEqual(@as(u64, 36), try budget.bytes_for_text_backing(8, 28));
    try std.testing.expectEqual(@as(u64, 48), try budget.bytes_for_list_backing(8, 4, 10));
    try std.testing.expectEqual(@as(u64, 24), try budget.bytes_for_canonical_buffer(8, 16));
}

test "checked cost formulas reject overflow" {
    try std.testing.expectError(error.ByteSizeOverflow, budget.bytes_for_task_frame(std.math.maxInt(u64), 1));
    try std.testing.expectError(error.ByteSizeOverflow, budget.bytes_for_queue_slots(std.math.maxInt(u64), 2));
    try std.testing.expectError(error.ByteSizeOverflow, budget.bytes_for_text_backing(1, std.math.maxInt(u64)));
    try std.testing.expectError(error.ByteSizeOverflow, budget.bytes_for_list_backing(1, std.math.maxInt(u64), 2));
    try std.testing.expectError(error.ByteSizeOverflow, budget.bytes_for_canonical_buffer(std.math.maxInt(u64), 1));
}

test "canonical buffer pool admits fixed result slots transactionally" {
    var bytes = budget.ByteBudget.init(32);
    var pool = try budget.CanonicalBufferPool.init(&bytes, 8, 24);

    var first = try pool.acquire();
    try std.testing.expectEqual(@as(u64, 32), bytes.committed_bytes());
    try std.testing.expectEqual(@as(u64, 1), pool.live_buffers());
    try std.testing.expectError(error.ByteBudgetExceeded, pool.acquire());
    try std.testing.expectEqual(@as(u64, 1), pool.live_buffers());

    try pool.release(&first);
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectEqual(@as(u64, 0), pool.live_buffers());
    try std.testing.expectError(error.AllocationInvariantViolation, pool.release(&first));
}

test "fixed allocation pools reject tokens owned by another pool" {
    var bytes = budget.ByteBudget.init(64);
    var frames = budget.FixedAllocationPool.init(&bytes, 16);
    var buffers = budget.CanonicalBufferPool.init(&bytes, 0, 16) catch unreachable;
    var frame = try frames.acquire();
    var buffer = try buffers.acquire();

    try std.testing.expectError(error.AllocationInvariantViolation, frames.release(&buffer));
    try std.testing.expectEqual(@as(u64, 1), frames.live_count());
    try std.testing.expectEqual(@as(u64, 1), buffers.live_buffers());

    try frames.release(&frame);
    try buffers.release(&buffer);
}

test "variable backing pools reserve by capacity and release exactly once" {
    var bytes = budget.ByteBudget.init(40);
    var text = budget.TextBackingPool.init(&bytes, 8);
    var text_allocation = try text.acquire(24);
    try std.testing.expectEqual(@as(u64, 32), bytes.committed_bytes());
    try std.testing.expectEqual(@as(u64, 1), text.live_backings());
    try std.testing.expectError(error.ByteBudgetExceeded, text.acquire(9));
    try std.testing.expectEqual(@as(u64, 32), bytes.committed_bytes());
    try text.release(&text_allocation);
    try std.testing.expectEqual(@as(u64, 0), text.live_backings());

    var list = budget.ListBackingPool.init(&bytes, 8, 4);
    var list_allocation = try list.acquire(8);
    try std.testing.expectEqual(@as(u64, 40), bytes.committed_bytes());
    try list.release(&list_allocation);
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectError(error.AllocationInvariantViolation, list.release(&list_allocation));
}

test "variable backing pools reject overflow and foreign tokens transactionally" {
    var bytes = budget.ByteBudget.init(std.math.maxInt(u64));
    var text = budget.TextBackingPool.init(&bytes, 1);
    try std.testing.expectError(error.ByteSizeOverflow, text.acquire(std.math.maxInt(u64)));
    try std.testing.expectEqual(@as(u64, 0), bytes.committed_bytes());
    try std.testing.expectEqual(@as(u64, 0), bytes.reserved_bytes());
    try std.testing.expectEqual(@as(u64, 0), text.live_backings());

    var list = budget.ListBackingPool.init(&bytes, 8, 4);
    var text_allocation = try text.acquire(8);
    var list_allocation = try list.acquire(1);
    try std.testing.expectError(error.AllocationInvariantViolation, text.release(&list_allocation));
    try std.testing.expectEqual(@as(u64, 1), text.live_backings());
    try std.testing.expectEqual(@as(u64, 1), list.live_backings());
    try text.release(&text_allocation);
    try list.release(&list_allocation);
}
