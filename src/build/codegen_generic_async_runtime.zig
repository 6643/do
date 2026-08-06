const std = @import("std");

test "generic runtime transitions pending to ready" {
    const runtime = @This();
    const waiting = try runtime.transition(.running, .host_pending);
    try std.testing.expectEqual(runtime.GenericRuntimeState.waiting, waiting);
    try std.testing.expectEqual(runtime.GenericRuntimeState.ready, try runtime.transition(waiting, .host_ready));
}

test "generic runtime transitions pending to cancelled" {
    const runtime = @This();
    const waiting = try runtime.transition(.running, .host_pending);
    const cancelling = try runtime.transition(waiting, .cancel_requested);
    try std.testing.expectEqual(runtime.GenericRuntimeState.cancelling, cancelling);
    try std.testing.expectEqual(runtime.GenericRuntimeState.cancelled, try runtime.transition(cancelling, .cancel_terminal));
}

test "generic runtime rejects duplicate terminal events" {
    const runtime = @This();
    try std.testing.expectError(
        error.GenericRuntimeInvalidTransition,
        runtime.transition(.terminal, .host_ready),
    );
}

test "generic runtime makes cancel-after-ready terminal without cancellation" {
    const runtime = @This();
    try std.testing.expectEqual(
        runtime.GenericRuntimeState.terminal,
        try runtime.transition(.ready, .cancel_requested),
    );
}

test "generic runtime turns host failure into terminal state" {
    const runtime = @This();
    try std.testing.expectEqual(
        runtime.GenericRuntimeState.terminal,
        try runtime.transition(.waiting, .host_failed),
    );
}

pub const GenericRuntimeState = enum {
    new,
    running,
    waiting,
    ready,
    cancelling,
    cancelled,
    terminal,
};

pub const GenericRuntimeEvent = union(enum) {
    host_pending,
    host_ready,
    host_failed,
    cancel_requested,
    cancel_terminal,
};

pub fn transition(state: GenericRuntimeState, event: GenericRuntimeEvent) !GenericRuntimeState {
    return switch (event) {
        .host_pending => switch (state) {
            .new, .running => .waiting,
            else => error.GenericRuntimeInvalidTransition,
        },
        .host_ready => switch (state) {
            .new, .running, .waiting => .ready,
            else => error.GenericRuntimeInvalidTransition,
        },
        .host_failed => switch (state) {
            .new, .running, .waiting, .cancelling => .terminal,
            else => error.GenericRuntimeInvalidTransition,
        },
        .cancel_requested => switch (state) {
            .running, .waiting => .cancelling,
            .ready => .terminal,
            else => error.GenericRuntimeInvalidTransition,
        },
        .cancel_terminal => switch (state) {
            .cancelling => .cancelled,
            else => error.GenericRuntimeInvalidTransition,
        },
    };
}
