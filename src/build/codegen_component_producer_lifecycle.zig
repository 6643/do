const std = @import("std");

pub const State = enum {
    init,
    calling,
    pending,
    ready,
    @"error",
    cancelled,
    dropped,
};

pub const Event = enum {
    begin_call,
    poll_pending,
    complete_ready,
    complete_error,
    request_cancel,
    early_drop,
    cleanup,
    unknown_terminal,
};

pub const TransitionError = error{
    AlreadyDropped,
    CallRequired,
    PendingRequired,
    TerminalRequired,
    UnknownTerminal,
};

pub fn advance(state: State, event: Event) TransitionError!State {
    if (state == .dropped) return error.AlreadyDropped;
    if (event == .unknown_terminal) return error.UnknownTerminal;

    return switch (state) {
        .init => switch (event) {
            .begin_call => .calling,
            else => error.CallRequired,
        },
        .calling => switch (event) {
            .poll_pending => .pending,
            .complete_ready => .ready,
            .complete_error => .@"error",
            .request_cancel, .early_drop => error.PendingRequired,
            .begin_call => error.CallRequired,
            .cleanup => error.TerminalRequired,
            .unknown_terminal => unreachable,
        },
        .pending => switch (event) {
            .poll_pending => .pending,
            .complete_ready => .ready,
            .complete_error => .@"error",
            .request_cancel => .cancelled,
            .early_drop => .dropped,
            .begin_call => error.CallRequired,
            .cleanup => error.TerminalRequired,
            .unknown_terminal => unreachable,
        },
        .ready, .@"error", .cancelled => switch (event) {
            .cleanup => .dropped,
            .poll_pending, .request_cancel, .early_drop => error.PendingRequired,
            .begin_call => error.CallRequired,
            .complete_ready, .complete_error => error.TerminalRequired,
            .unknown_terminal => unreachable,
        },
        .dropped => unreachable,
    };
}

pub fn validate_path(events: []const Event) TransitionError!State {
    var state: State = .init;
    for (events) |event| state = try advance(state, event);
    return state;
}

test "lifecycle transition table has all states and events" {
    try std.testing.expect(@typeInfo(State).@"enum".field_names.len == 7);
    try std.testing.expect(@typeInfo(Event).@"enum".field_names.len == 8);
}
