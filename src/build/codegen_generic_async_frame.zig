const std = @import("std");
const async_model = @import("codegen_async_model.zig");
const runtime = @import("codegen_generic_async_runtime.zig");

pub const GenericAsyncState = runtime.GenericRuntimeState;

pub const GenericAsyncFrame = struct {
    waitable_set_offset: u32,
    subtask_offset: u32,
    state_offset: u32,
    terminal_offset: u32,
    size: u32,
    state: GenericAsyncState = .new,
    waitable_set: ?u32 = null,
    subtask: ?u32 = null,
    terminal: bool = false,

    pub fn init() !GenericAsyncFrame {
        return .{
            .waitable_set_offset = 0,
            .subtask_offset = 4,
            .state_offset = 8,
            .terminal_offset = 12,
            .size = try async_model.align_frame_size(16, 8),
        };
    }

    pub fn start(self: *GenericAsyncFrame) !void {
        if (self.state != .new) return error.AsyncFrameInvalidTransition;
        self.state = .running;
    }

    pub fn @"suspend"(self: *GenericAsyncFrame) !void {
        try self.apply_event(.host_pending);
    }

    pub fn resume_ready(self: *GenericAsyncFrame) !void {
        try self.apply_event(.host_ready);
    }

    pub fn fail(self: *GenericAsyncFrame) !void {
        try self.apply_event(.host_failed);
    }

    pub fn cancel(self: *GenericAsyncFrame) !void {
        if (self.state == .terminal or self.terminal) return error.AsyncFrameAlreadyTerminal;
        if (self.state == .cancelled) return error.AsyncFrameAlreadyCancelled;
        try self.apply_event(.cancel_requested);
    }

    pub fn observe_cancel(self: *GenericAsyncFrame) !void {
        try self.apply_event(.cancel_terminal);
    }

    fn apply_event(self: *GenericAsyncFrame, event: runtime.GenericRuntimeEvent) !void {
        const next = runtime.transition(self.state, event) catch |err| {
            return switch (err) {
                error.GenericRuntimeInvalidTransition => error.AsyncFrameInvalidTransition,
            };
        };
        self.state = next;
    }

    pub fn cleanup(self: *GenericAsyncFrame) !void {
        switch (self.state) {
            .ready, .cancelled, .terminal => {
                if (self.terminal) return error.AsyncFrameAlreadyTerminal;
                self.terminal = true;
                self.waitable_set = null;
                self.subtask = null;
                self.state = .terminal;
            },
            else => return error.AsyncFrameInvalidTransition,
        }
    }
};

pub const GenericAsyncFrameOwner = struct {
    active: bool = false,

    pub fn acquire(self: *GenericAsyncFrameOwner) !GenericAsyncFrame {
        if (self.active) return error.GenericAsyncFrameAlreadyActive;
        self.active = true;
        return GenericAsyncFrame.init();
    }

    pub fn release(self: *GenericAsyncFrameOwner) !void {
        if (!self.active) return error.GenericAsyncFrameNotActive;
        self.active = false;
    }
};

test "generic frame has one terminal cleanup" {
    var frame = try GenericAsyncFrame.init();
    try frame.start();
    try frame.@"suspend"();
    try frame.resume_ready();
    try frame.cleanup();
    try std.testing.expectEqual(GenericAsyncState.terminal, frame.state);
    try std.testing.expect(frame.terminal);
    try std.testing.expectError(error.AsyncFrameAlreadyTerminal, frame.cleanup());
}

test "generic frame cancellation reaches terminal exactly once" {
    var frame = try GenericAsyncFrame.init();
    try frame.start();
    try frame.cancel();
    try std.testing.expectEqual(GenericAsyncState.cancelling, frame.state);
    try frame.observe_cancel();
    try std.testing.expectEqual(GenericAsyncState.cancelled, frame.state);
    try frame.cleanup();
    try std.testing.expectEqual(GenericAsyncState.terminal, frame.state);
    try std.testing.expectError(error.AsyncFrameAlreadyTerminal, frame.cancel());
}

test "generic frame rejects resume after cancellation and early cleanup" {
    var frame = try GenericAsyncFrame.init();
    try std.testing.expectError(error.AsyncFrameInvalidTransition, frame.cleanup());
    try frame.start();
    try frame.@"suspend"();
    try frame.cancel();
    try std.testing.expectError(error.AsyncFrameInvalidTransition, frame.resume_ready());
    try frame.observe_cancel();
    try frame.cleanup();
}

test "generic frame reserves waitable set, subtask, state, and terminal slots" {
    const frame = try GenericAsyncFrame.init();
    try std.testing.expectEqual(@as(u32, 0), frame.waitable_set_offset);
    try std.testing.expectEqual(@as(u32, 4), frame.subtask_offset);
    try std.testing.expectEqual(@as(u32, 8), frame.state_offset);
    try std.testing.expectEqual(@as(u32, 12), frame.terminal_offset);
    try std.testing.expectEqual(@as(u32, 16), frame.size);
}

test "generic frame owner rejects a second active root frame" {
    var owner = GenericAsyncFrameOwner{};
    _ = try owner.acquire();
    try std.testing.expectError(error.GenericAsyncFrameAlreadyActive, owner.acquire());
    try owner.release();
    _ = try owner.acquire();
}
