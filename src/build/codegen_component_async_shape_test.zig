const std = @import("std");
const shape = @import("codegen_component_async_shape.zig");

fn expect_layout(
    actual: shape.BoundedAsyncShape,
    mode: shape.BoundedAsyncMode,
    size: u32,
    argument_offset: ?u32,
) !void {
    try std.testing.expectEqual(mode, actual.mode);
    try std.testing.expectEqual(@as(u32, 4), actual.frame.alignment);
    try std.testing.expectEqual(@as(u32, 0), actual.frame.waitable_set_offset);
    try std.testing.expectEqual(@as(u32, 4), actual.frame.active_subtask_offset);
    try std.testing.expectEqual(@as(u32, 8), actual.frame.phase_offset);
    try std.testing.expectEqual(size, actual.frame.size);
    try std.testing.expectEqual(argument_offset, actual.frame.u32_argument_offset);
    try actual.validate();
}

fn expect_actions(
    actual: []const shape.BoundedCleanupAction,
    expected: []const shape.BoundedCleanupAction,
) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, 0..) |action, index| {
        try std.testing.expectEqual(action, actual[index]);
    }
}

test "bounded child unit shape reserves the 16-byte root frame" {
    const actual = try shape.child_shape(false);
    try expect_layout(actual, .child, 16, null);
    try expect_actions(actual.cleanup.normal, &.{
        .drop_active_subtask_if_owned,
        .drop_waitable_set,
        .clear_root_context,
        .free_root_frame,
        .root_task_return,
    });
    try expect_actions(actual.cleanup.phase_transition, &.{});
    try expect_actions(actual.cleanup.cancelled, &.{});
}

test "bounded child scalar shape reserves the u32 slot at plus twelve" {
    const actual = try shape.child_shape(true);
    try expect_layout(actual, .child, 20, 12);
}

test "bounded inline unit shape separates transition and terminal cleanup" {
    const actual = try shape.inline_shape(false);
    try expect_layout(actual, .inline_call, 16, null);
    try expect_actions(actual.cleanup.phase_transition, &.{
        .drop_active_subtask_if_owned,
        .drop_waitable_set,
        .create_next_waitable_set,
        .start_next_child,
    });
    try expect_actions(actual.cleanup.cancelled, &.{
        .cancel_active_subtask,
        .drop_active_subtask_if_owned,
        .drop_waitable_set,
        .clear_root_context,
        .free_root_frame,
        .root_task_cancel,
    });
}

test "bounded inline scalar shape keeps the u32 slot at plus twelve" {
    const actual = try shape.inline_shape(true);
    try expect_layout(actual, .inline_call, 20, 12);
}

test "bounded host scalar shape uses host cancellation cleanup" {
    const actual = try shape.host_scalar_shape();
    try expect_layout(actual, .host_scalar, 20, 12);
    try expect_actions(actual.cleanup.cancelled, &.{
        .cancel_active_subtask,
        .drop_active_subtask_if_owned,
        .drop_waitable_set,
        .clear_root_context,
        .free_root_frame,
        .root_task_cancel,
    });
}

test "bounded shape rejects a scalar slot outside a 16-byte frame" {
    var actual = try shape.child_shape(false);
    actual.frame.u32_argument_offset = 12;
    try std.testing.expectError(error.InvalidFrameSize, actual.validate());
}

test "bounded shape rejects non-four-byte alignment" {
    var actual = try shape.child_shape(false);
    actual.frame.alignment = 8;
    try std.testing.expectError(error.InvalidFrameAlignment, actual.validate());
}

test "bounded shape rejects a non-common frame slot" {
    var actual = try shape.child_shape(false);
    actual.frame.waitable_set_offset = 4;
    try std.testing.expectError(error.InvalidFrameSlot, actual.validate());
}

test "bounded shape rejects duplicate terminal actions" {
    var actual = try shape.host_scalar_shape();
    const normal = [_]shape.BoundedCleanupAction{
        .drop_active_subtask_if_owned,
        .drop_waitable_set,
        .clear_root_context,
        .free_root_frame,
        .root_task_return,
        .root_task_return,
    };
    actual.cleanup.normal = &normal;
    try std.testing.expectError(error.InvalidCleanupOrder, actual.validate());
}

test "bounded shape rejects a terminal action in resume" {
    var actual = try shape.inline_shape(false);
    const phase_transition = [_]shape.BoundedCleanupAction{.root_task_return};
    actual.cleanup.phase_transition = &phase_transition;
    try std.testing.expectError(error.InvalidCleanupOrder, actual.validate());
}

test "bounded shape rejects child transition actions in cancellation" {
    var actual = try shape.host_scalar_shape();
    const cancelled = [_]shape.BoundedCleanupAction{
        .cancel_active_subtask,
        .start_next_child,
        .root_task_cancel,
    };
    actual.cleanup.cancelled = &cancelled;
    try std.testing.expectError(error.InvalidCleanupOrder, actual.validate());
}

test "bounded shape rejects a non-inline resume sequence" {
    var actual = try shape.child_shape(false);
    const phase_transition = [_]shape.BoundedCleanupAction{.start_next_child};
    actual.cleanup.phase_transition = &phase_transition;
    try std.testing.expectError(error.InvalidCleanupOrder, actual.validate());
}
