const std = @import("std");
const async_model = @import("codegen_async_model.zig");

pub const GenericAsyncState = enum {
    created,
    running,
    suspended,
    ready,
    cancelled,
    terminal,
};

pub const GenericAsyncFrame = struct {
    state_offset: u32,
    future_offset: u32,
    terminal_offset: u32,
    size: u32,
    state: GenericAsyncState = .created,
    terminal: bool = false,

    pub fn init() !GenericAsyncFrame {
        return .{
            .state_offset = 0,
            .future_offset = 4,
            .terminal_offset = 8,
            .size = try async_model.align_frame_size(12, 8),
        };
    }

    pub fn start(self: *GenericAsyncFrame) !void {
        if (self.state != .created) return error.AsyncFrameInvalidTransition;
        self.state = .running;
    }

    pub fn @"suspend"(self: *GenericAsyncFrame) !void {
        if (self.state != .running) return error.AsyncFrameInvalidTransition;
        self.state = .suspended;
    }

    pub fn resume_ready(self: *GenericAsyncFrame) !void {
        if (self.state != .suspended) return error.AsyncFrameInvalidTransition;
        self.state = .ready;
    }

    pub fn cancel(self: *GenericAsyncFrame) !void {
        switch (self.state) {
            .created, .running, .suspended, .ready => self.state = .cancelled,
            .cancelled => return error.AsyncFrameAlreadyCancelled,
            .terminal => return error.AsyncFrameAlreadyTerminal,
        }
    }

    pub fn cleanup(self: *GenericAsyncFrame) !void {
        switch (self.state) {
            .ready, .cancelled => {
                if (self.terminal) return error.AsyncFrameAlreadyTerminal;
                self.terminal = true;
                self.state = .terminal;
            },
            .terminal => return error.AsyncFrameAlreadyTerminal,
            else => return error.AsyncFrameInvalidTransition,
        }
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
    try frame.cleanup();
}
