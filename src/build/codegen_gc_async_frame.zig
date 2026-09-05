const std = @import("std");
const generated_text = @import("codegen_text.zig");
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
    try generated_text.append_block(allocator, out, 2,
        \\  (type $async-frame (struct
        \\    (field $state (mut i32))
        \\    (field $waitable-set (mut i32))
        \\    (field $cleanup-flags (mut i32))
        \\    (field $completion-value (mut i32))
        \\
    );
    for (layout.slots) |slot| {
        const core_type = frame_slot_core_type(slot.storage) orelse return error.UnsupportedAsyncGcFrameSlot;
        try generated_text.append_fmt(allocator, out, "    (field $slot-{[name]s} (mut {[core_type]s}))\n", .{ .name = slot.name, .core_type = core_type });
    }
    try generated_text.append_block(allocator, out, 4,
        \\    (field $gc-root (mut (ref null any)))
        \\    (field $resource-state (mut i32))
        \\
    );
    try generated_text.append_fmt_block(
        allocator,
        out,
        2,
        \\  ))
        \\  ;; [gc-root][suspend_frame]
        \\  ;; [gc-root][resume_frame]
        \\  ;; [gc-root][cancel_frame]
        \\  ;; [gc-root][terminal]
        \\  ;; [resource-drop-exactly-once]
        \\  ;; [async-frame-bytes] {[frame_bytes]d}
        \\  (table $async-frames 0 (ref null $async-frame))
        \\
        ,
        .{ .frame_bytes = frame_bytes },
    );
}

pub fn emit_frame_table_allocator(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try generated_text.append_block(allocator, out, 2,
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
        \\    (local $frame (ref $async-frame))
        \\    ;; [gc-root][cancel_frame]
        \\    ;; [gc-root][terminal]
        \\    ;; [resource-drop-exactly-once]
        \\    local.get $handle
        \\    table.get $async-frames
        \\    ref.as_non_null
        \\    local.tee $frame
        \\    ref.null any
        \\    struct.set $async-frame $gc-root
        \\    local.get $frame
        \\    i32.const 0
        \\    struct.set $async-frame $resource-state
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
    try generated_text.append_fmt_block(allocator, out, 2,
        \\  ;; [async-frame-budget-bytes] {[frame_bytes]d}
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
        \\    i64.const {[frame_bytes]d}
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
        \\      i64.const {[frame_bytes]d}
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
        \\    (local $frame (ref $async-frame))
        \\    ;; [gc-root][cancel_frame]
        \\    ;; [gc-root][terminal]
        \\    ;; [resource-drop-exactly-once]
        \\    local.get $handle
        \\    table.get $async-frames
        \\    ref.as_non_null
        \\    local.tee $frame
        \\    ref.null any
        \\    struct.set $async-frame $gc-root
        \\    local.get $frame
        \\    i32.const 0
        \\    struct.set $async-frame $resource-state
        \\    i64.const {[frame_bytes]d}
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
    , .{ .frame_bytes = frame_bytes });
}

/// Append the two trailing metadata values required by every GC async-frame
/// constructor. Keeping this as a single transformation avoids per-template
/// field-order drift when a bounded emitter has multiple constructor paths.
pub fn inject_frame_constructor_initializers(
    allocator: std.mem.Allocator,
    input: []const u8,
) ![]u8 {
    const needle = "struct.new $async-frame";
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, cursor, needle)) |index| {
        try out.appendSlice(allocator, input[cursor..index]);

        const line_start = if (std.mem.lastIndexOfScalar(u8, input[0..index], '\n')) |newline| newline + 1 else 0;
        const indent = input[line_start..index];
        for (indent) |byte| {
            if (byte != ' ' and byte != '\t') return error.InvalidAsyncFrameConstructor;
        }

        try out.appendSlice(allocator, "ref.null any\n");
        try out.appendSlice(allocator, indent);
        try out.appendSlice(allocator, "i32.const 0\n");
        try out.appendSlice(allocator, indent);
        try out.appendSlice(allocator, needle);
        cursor = index + needle.len;
    }

    try out.appendSlice(allocator, input[cursor..]);
    return out.toOwnedSlice(allocator);
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
