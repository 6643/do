const std = @import("std");
const async_model = @import("codegen_async_model.zig");
const async_byte_budget = @import("async_byte_budget.zig");

pub const async_frame_header_bytes: u64 = 16;

pub fn bytes_for_frame_layout(layout: async_model.FrameLayout) !u64 {
    const frame_size: u64 = layout.size;
    if (frame_size < async_frame_header_bytes) return error.InvalidAsyncFrameLayout;
    return async_byte_budget.bytes_for_task_frame(
        async_frame_header_bytes,
        frame_size - async_frame_header_bytes,
    );
}

pub const TaskFramePool = struct {
    pool: async_byte_budget.FixedAllocationPool,

    pub fn init(budget: *async_byte_budget.ByteBudget, frame_bytes: u64) TaskFramePool {
        return .{ .pool = async_byte_budget.FixedAllocationPool.init(budget, frame_bytes) };
    }

    pub fn live_frames(self: *const TaskFramePool) u64 {
        return self.pool.live_count();
    }

    pub fn acquire(self: *TaskFramePool) async_byte_budget.Error!async_byte_budget.Allocation {
        return self.pool.acquire();
    }

    pub fn release(
        self: *TaskFramePool,
        allocation: *async_byte_budget.Allocation,
    ) async_byte_budget.Error!void {
        return self.pool.release(allocation);
    }
};

pub fn emit_frame_table_layout(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layout: async_model.FrameLayout,
) !void {
    const frame_bytes = try bytes_for_frame_layout(layout);
    try out.appendSlice(allocator, "  (type $async-frame (struct\n");
    try out.appendSlice(allocator, "    (field $state (mut i32))\n");
    try out.appendSlice(allocator, "    (field $waitable-set (mut i32))\n");
    try out.appendSlice(allocator, "    (field $cleanup-flags (mut i32))\n");
    try out.appendSlice(allocator, "    (field $completion-value (mut i32))\n");
    for (layout.slots) |slot| {
        const core_type = frame_slot_core_type(slot.storage) orelse return error.UnsupportedAsyncGcFrameSlot;
        try append_fmt(allocator, out, "    (field $slot-{s} (mut {s}))\n", .{ slot.name, core_type });
    }
    try out.appendSlice(allocator, "  ))\n");
    try append_fmt(allocator, out, "  ;; [async-frame-bytes] {d}\n", .{frame_bytes});
    try out.appendSlice(allocator, "  (table $async-frames 0 (ref null $async-frame))\n");
}

pub fn emit_frame_table_allocator(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\  (type $async-free-slot (struct
        \\    (field $handle i32)
        \\    (field $next (ref null $async-free-slot))
        \\  ))
        \\  (global $async-frame-free-head (mut (ref null $async-free-slot)) (ref.null $async-free-slot))
        \\  (func $frame-alloc (param $frame (ref $async-frame)) (result i32)
        \\    (local $handle i32)
        \\    (local $node (ref $async-free-slot))
        \\    global.get $async-frame-free-head
        \\    ref.is_null
        \\    if (result i32)
        \\      local.get $frame
        \\      i32.const 1
        \\      table.grow $async-frames
        \\    else
        \\      global.get $async-frame-free-head
        \\      ref.as_non_null
        \\      local.tee $node
        \\      struct.get $async-free-slot $next
        \\      global.set $async-frame-free-head
        \\      local.get $node
        \\      struct.get $async-free-slot $handle
        \\    end
        \\    local.set $handle
        \\    local.get $handle
        \\    local.get $frame
        \\    table.set $async-frames
        \\    local.get $handle)
        \\  (func $frame-free (param $handle i32)
        \\    (local $node (ref $async-free-slot))
        \\    i64.const {d}
        \\    call $async-byte-budget-release
        \\    local.get $handle
        \\    ref.null $async-frame
        \\    table.set $async-frames
        \\    local.get $handle
        \\    global.get $async-frame-free-head
        \\    struct.new $async-free-slot
        \\    local.set $node
        \\    local.get $node
        \\    global.set $async-frame-free-head)
    );
}

pub fn emit_frame_table_allocator_with_bytes(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    frame_bytes: u64,
) !void {
    const runtime = try std.fmt.allocPrint(allocator,
        \\  ;; [async-frame-budget-bytes] {d}
        \\  ;; [async-byte-budget-limit] -1
        \\  (global $async-byte-budget-used (mut i64) (i64.const 0))
        \\  (global $async-byte-budget-limit (mut i64) (i64.const -1))
        \\  (func $async-byte-budget-limit (export "[async-config]byte-budget-limit") (param $limit i64) (result i32)
        \\    local.get $limit
        \\    i64.const -1
        \\    i64.eq
        \\    if (result i32)
        \\      local.get $limit
        \\      global.set $async-byte-budget-limit
        \\      i32.const 1
        \\    else
        \\      local.get $limit
        \\      i64.const 0
        \\      i64.lt_s
        \\      if (result i32)
        \\        i32.const 0
        \\      else
        \\        global.get $async-byte-budget-used
        \\        local.get $limit
        \\        i64.gt_u
        \\        if (result i32)
        \\          i32.const 0
        \\        else
        \\          local.get $limit
        \\          global.set $async-byte-budget-limit
        \\          i32.const 1
        \\        end
        \\      end
        \\    end
        \\  )
        \\  (func (export "byte-budget-limit") (param $limit i64) (result i32)
        \\    local.get $limit
        \\    call $async-byte-budget-limit)
        \\  (func $async-byte-budget-reserve (param $bytes i64) (result i32)
        \\    (local $next i64)
        \\    global.get $async-byte-budget-used
        \\    local.get $bytes
        \\    i64.add
        \\    local.tee $next
        \\    global.get $async-byte-budget-used
        \\    i64.lt_u
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      global.get $async-byte-budget-limit
        \\      i64.const -1
        \\      i64.eq
        \\      if (result i32)
        \\        i32.const 1
        \\      else
        \\        local.get $next
        \\        global.get $async-byte-budget-limit
        \\        i64.le_u
        \\      end
        \\      if (result i32)
        \\        local.get $next
        \\        global.set $async-byte-budget-used
        \\        i32.const 1
        \\      else
        \\        i32.const 0
        \\      end
        \\    end
        \\  )
        \\  (func $async-byte-budget-release (param $bytes i64)
        \\    global.get $async-byte-budget-used
        \\    local.get $bytes
        \\    i64.lt_u
        \\    if unreachable end
        \\    global.get $async-byte-budget-used
        \\    local.get $bytes
        \\    i64.sub
        \\    global.set $async-byte-budget-used
        \\  )
        \\  (type $async-free-slot (struct
        \\    (field $handle i32)
        \\    (field $next (ref null $async-free-slot))
        \\  ))
        \\  (global $async-frame-free-head (mut (ref null $async-free-slot)) (ref.null $async-free-slot))
        \\  (func $frame-alloc (param $frame (ref $async-frame)) (result i32)
        \\    (local $handle i32)
        \\    (local $node (ref $async-free-slot))
        \\    i64.const {d}
        \\    call $async-byte-budget-reserve
        \\    i32.eqz
        \\    if unreachable end
        \\    global.get $async-frame-free-head
        \\    ref.is_null
        \\    if (result i32)
        \\      local.get $frame
        \\      i32.const 1
        \\      table.grow $async-frames
        \\    else
        \\      global.get $async-frame-free-head
        \\      ref.as_non_null
        \\      local.tee $node
        \\      struct.get $async-free-slot $next
        \\      global.set $async-frame-free-head
        \\      local.get $node
        \\      struct.get $async-free-slot $handle
        \\    end
        \\    local.set $handle
        \\    local.get $handle
        \\    i32.const -1
        \\    i32.eq
        \\    if
        \\      i64.const {d}
        \\      call $async-byte-budget-release
        \\      unreachable
        \\    end
        \\    local.get $handle
        \\    local.get $frame
        \\    table.set $async-frames
        \\    local.get $handle
        \\  )
        \\  (func $frame-free (param $handle i32)
        \\    (local $node (ref $async-free-slot))
        \\    i64.const {d}
        \\    call $async-byte-budget-release
        \\    local.get $handle
        \\    ref.null $async-frame
        \\    table.set $async-frames
        \\    local.get $handle
        \\    global.get $async-frame-free-head
        \\    struct.new $async-free-slot
        \\    local.set $node
        \\    local.get $node
        \\    global.set $async-frame-free-head
        \\  )
    , .{ frame_bytes, frame_bytes, frame_bytes, frame_bytes });
    defer allocator.free(runtime);
    try out.appendSlice(allocator, runtime);
}

fn frame_slot_core_type(storage: async_model.FrameSlotStorage) ?[]const u8 {
    return switch (storage) {
        .i32 => "i32",
        .i64 => "i64",
        .f32 => "f32",
        .f64 => "f64",
        .waitable, .unsupported => null,
    };
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
