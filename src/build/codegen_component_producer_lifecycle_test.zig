const std = @import("std");
const lifecycle = @import("codegen_component_producer_lifecycle.zig");

fn expect_path(events: []const lifecycle.Event) !void {
    try std.testing.expectEqual(lifecycle.State.dropped, try lifecycle.validate_path(events));
}

test "normal pending ready cleanup reaches dropped" {
    try expect_path(&.{ .begin_call, .poll_pending, .complete_ready, .cleanup });
}

test "pending cancellation cleanup reaches dropped" {
    try expect_path(&.{ .begin_call, .poll_pending, .request_cancel, .cleanup });
}

test "pending early drop reaches dropped" {
    try expect_path(&.{ .begin_call, .poll_pending, .early_drop });
}

test "calling can complete directly without pending" {
    try expect_path(&.{ .begin_call, .complete_ready, .cleanup });
}

test "ready cannot be polled or cancelled" {
    try std.testing.expectError(
        lifecycle.TransitionError.PendingRequired,
        lifecycle.validate_path(&.{ .begin_call, .complete_ready, .poll_pending }),
    );
    try std.testing.expectError(
        lifecycle.TransitionError.PendingRequired,
        lifecycle.validate_path(&.{ .begin_call, .complete_ready, .request_cancel }),
    );
}

test "dropped rejects every event" {
    try std.testing.expectError(
        lifecycle.TransitionError.AlreadyDropped,
        lifecycle.validate_path(&.{ .begin_call, .complete_ready, .cleanup, .cleanup }),
    );
}

test "cancel without pending is rejected" {
    try std.testing.expectError(
        lifecycle.TransitionError.PendingRequired,
        lifecycle.validate_path(&.{ .begin_call, .request_cancel }),
    );
}

test "cleanup before terminal is rejected" {
    try std.testing.expectError(
        lifecycle.TransitionError.TerminalRequired,
        lifecycle.validate_path(&.{ .begin_call, .cleanup }),
    );
}

test "unknown terminal is rejected" {
    try std.testing.expectError(
        lifecycle.TransitionError.UnknownTerminal,
        lifecycle.advance(.pending, .unknown_terminal),
    );
}
