const std = @import("std");
const async_model = @import("codegen_async_model.zig");
const gc_async_frame = @import("codegen_gc_async_frame.zig");

pub fn emit_generic_async_frame_metadata(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state_offset: u32,
    future_offset: u32,
    terminal_offset: u32,
    size: u32,
) !void {
    try append_fmt(allocator, out, "  ;; [generic-async-frame-layout] state={d} future={d} terminal={d} size={d}\n", .{
        state_offset,
        future_offset,
        terminal_offset,
        size,
    });
}

pub fn emit_frame_metadata(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: async_model.AsyncFunctionPlan,
) !void {
    try append_fmt(allocator, out, "  ;; [async-frame] {s}\n", .{plan.name});
    for (plan.frame.resume_states) |state| {
        try append_fmt(allocator, out, "  ;; [async-state] {d}\n", .{state.id});
    }
    try append_fmt(allocator, out, "  ;; [async-cleanup] {d}\n", .{plan.frame.cleanup_state});
    for (plan.layout.slots) |slot| {
        try append_fmt(allocator, out, "  ;; [async-slot] {s} offset={d}\n", .{ slot.name, slot.offset });
    }
}

pub const AsyncTerminalReason = enum {
    returned,
    failed,
    cancelled,
};

pub const StreamWriterFrameLayout = struct {
    result_tag: u32 = 0,
    result_payload: u32 = 1,
    waitable_set: u32 = 8,
    stream_readable: u32 = 12,
    stream_writable: u32 = 16,
    queue_head: u32 = 20,
    queue_count: u32 = 24,
    queue_capacity: u32 = 28,
    pending_producer: u32 = 32,
    terminal_state: u32 = 36,
    error_payload: u32 = 40,
    pending_ptr: u32 = 44,
    pending_len: u32 = 48,
    producer_index: u32 = 52,
    producer_value: u32 = 60,
    size: u32 = 64,
};

pub const stream_writer_frame_layout = StreamWriterFrameLayout{};

pub fn emit_stream_writer_frame_metadata(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layout: StreamWriterFrameLayout,
    capacity: u32,
) !void {
    try append_fmt(allocator, out, "  ;; [writer-result-tag-offset] {d}\n", .{layout.result_tag});
    try append_fmt(allocator, out, "  ;; [writer-result-payload-offset] {d}\n", .{layout.result_payload});
    try append_fmt(allocator, out, "  ;; Frame layout: writer queue head/count/capacity at {d}/{d}/{d}; pending producer at {d}; terminal/error at {d}/{d}.\n", .{
        layout.queue_head,
        layout.queue_count,
        layout.queue_capacity,
        layout.pending_producer,
        layout.terminal_state,
        layout.error_payload,
    });
    try append_fmt(allocator, out, "  ;; [writer-capacity] {d}\n", .{capacity});
    try append_fmt(allocator, out, "  ;; [writer-frame-size] {d}\n", .{layout.size});
    try append_fmt(allocator, out, "  ;; [writer-producer-index-offset] {d}\n", .{layout.producer_index});
    try append_fmt(allocator, out, "  ;; [writer-producer-value-offset] {d}\n", .{layout.producer_value});
}

pub fn emit_async_terminal_cleanup(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    frame: async_model.FrameModel,
    reason: AsyncTerminalReason,
) !void {
    try append_fmt(allocator, out, "  ;; [async-terminal] {s}\n", .{@tagName(reason)});
    if (frame.resume_states.len != 0) {
        const active_defers = frame.resume_states[frame.resume_states.len - 1].active_defers;
        var index = active_defers.len;
        while (index != 0) {
            index -= 1;
            try append_fmt(allocator, out, "  ;; [async-defer] defer {d}\n", .{active_defers[index].token_index});
        }
    }
    try out.appendSlice(allocator, "  local.get $frame\n  call $frame-free\n");
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

test "async terminal cleanup releases defers in reverse order before the frame" {
    const defers = [_]async_model.DeferSite{
        .{ .token_index = 11 },
        .{ .token_index = 29 },
    };
    var states = [_]async_model.ResumeState{.{
        .id = 1,
        .token_index = 40,
        .live_slots = &.{},
        .active_defers = &defers,
    }};
    const frame = async_model.FrameModel{ .resume_states = &states, .cleanup_state = 2 };
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try emit_async_terminal_cleanup(std.testing.allocator, &wat, frame, .cancelled);

    const later = std.mem.indexOf(u8, wat.items, "defer 29").?;
    const earlier = std.mem.indexOf(u8, wat.items, "defer 11").?;
    const release = std.mem.indexOf(u8, wat.items, "call $frame-free").?;
    try std.testing.expect(later < earlier and earlier < release);
}

test "generic async frame metadata records the aligned ownership slots" {
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try emit_generic_async_frame_metadata(std.testing.allocator, &wat, 0, 4, 8, 16);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "state=0 future=4 terminal=8 size=16") != null);
}

test "stream writer frame metadata records bounded queue state" {
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try emit_stream_writer_frame_metadata(std.testing.allocator, &wat, stream_writer_frame_layout, 1);

    try std.testing.expect(std.mem.indexOf(u8, wat.items, "queue head/count/capacity at 20/24/28") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "pending producer at 32; terminal/error at 36/40") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[writer-result-tag-offset] 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[writer-result-payload-offset] 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[writer-capacity] 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[writer-frame-size] 64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[writer-producer-value-offset] 60") != null);
}

test "stream writer result frame uses the compact canonical layout" {
    try std.testing.expectEqual(@as(u32, 0), stream_writer_frame_layout.result_tag);
    try std.testing.expectEqual(@as(u32, 1), stream_writer_frame_layout.result_payload);
}

test "GC frame table layout retains scalar live slots as GC struct fields" {
    var slots = [_]async_model.FrameLayoutSlot{
        .{ .name = "count", .storage = .i32, .offset = 16 },
        .{ .name = "deadline", .storage = .i64, .offset = 24 },
    };
    const layout = async_model.FrameLayout{ .size = 32, .slots = &slots };
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try gc_async_frame.emit_frame_table_layout(std.testing.allocator, &wat, layout);

    try std.testing.expect(std.mem.indexOf(u8, wat.items, "(type $async-frame (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "(field $slot-count (mut i32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "(field $slot-deadline (mut i64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "(table $async-frames 0 (ref null $async-frame))") != null);
}

test "GC frame table allocator clears roots before returning slot handles" {
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);

    try gc_async_frame.emit_frame_table_allocator(std.testing.allocator, &wat);

    const clear = std.mem.indexOf(u8, wat.items, "ref.null $async-frame\n    table.set $async-frames").?;
    const recycle = clear + std.mem.indexOf(u8, wat.items[clear..], "global.set $async-frame-free-head").?;
    try std.testing.expect(clear < recycle);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "table.grow $async-frames") != null);
}
