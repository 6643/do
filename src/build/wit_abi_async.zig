const std = @import("std");

pub const AsyncError = error{
    InvalidEndpoint,
    DuplicateEndpoint,
    UnknownEndpoint,
    InvalidTransition,
    PollAfterTerminal,
    DoubleCancellation,
    TerminalAlreadyConsumed,
    ChildBeforeParent,
    UnclosedOwner,
    OwnerStillActive,
    UnfinishedEndpoint,
    DoubleCleanup,
    SecondQueueItem,
};

pub const EndpointKind = enum {
    future,
    stream,
    resource,
};

pub const AsyncState = enum {
    pending,
    ready,
    failed,
    cancelled,
    consumed,
    dropped,
    closed,
};

pub const NameEvent = struct {
    name: []const u8,
};

pub const EndpointSpec = struct {
    name: []const u8,
    kind: EndpointKind,
    parent: ?[]const u8 = null,
    owns_resource: bool = false,
};

pub const Event = union(enum) {
    poll: NameEvent,
    ready: NameEvent,
    completion_error: NameEvent,
    cancel: NameEvent,
    consume: NameEvent,
    drop: NameEvent,
    close_owner: NameEvent,
};

pub const AsyncActionKind = enum {
    poll,
    ready,
    completion_error,
    cancel,
    consume,
    drop,
    close_owner,
    cleanup,
};

pub const AsyncAction = struct {
    kind: AsyncActionKind,
    name: []const u8,
};

pub const EndpointStatus = struct {
    name: []const u8,
    kind: EndpointKind,
    parent: ?[]const u8,
    state: AsyncState = .pending,
    endpoint_cleaned: bool = false,
    owner_open: bool = false,
    cleanup_count: u32 = 0,
};

pub const AsyncPlan = struct {
    actions: []AsyncAction,
    endpoints: []EndpointStatus,

    pub fn deinit(self: *AsyncPlan, allocator: std.mem.Allocator) void {
        if (self.actions.len != 0) allocator.free(self.actions);
        if (self.endpoints.len != 0) allocator.free(self.endpoints);
        self.actions = &.{};
        self.endpoints = &.{};
    }

    pub fn state(self: *const AsyncPlan, name: []const u8) ?AsyncState {
        const endpoint = find_endpoint(self.endpoints, name) orelse return null;
        return endpoint.state;
    }

    pub fn cleanup_count(self: *const AsyncPlan, name: []const u8) ?u32 {
        const endpoint = find_endpoint(self.endpoints, name) orelse return null;
        return endpoint.cleanup_count;
    }
};

pub const ListProducerFramePhase = enum {
    empty,
    allocated,
    queued,
    transferred,
    awaiting,
    completed,
    cancelled,
    dropped,
    finalized,
};

pub const ListProducerCallbackState = enum {
    none,
    pending,
    ready,
    failed,
    cancelled,
    dropped,
};

pub const ListProducerFutureState = enum {
    none,
    pending,
    ready,
    failed,
    dropped,
};

pub const ListProducerFrameActionKind = enum {
    allocate_list,
    queue,
    transfer,
    register_waitable,
    await_sink,
    callback_ready,
    callback_error,
    callback_cancel,
    callback_drop,
    clear_source_slots,
    release_list,
    drop_sink_future,
    unregister_waitable,
    drop_stream_writer,
    drop_frame,
    terminal_finalize,
};

pub const ListProducerFrameAction = struct {
    kind: ListProducerFrameActionKind,
};

pub const ListProducerFrameOperation = union(enum) {
    allocate: void,
    queue: void,
    transfer: void,
    await_sink: void,
    complete: ListProducerCallbackState,
    cancel: void,
    early_drop: void,
    finalize: void,
};

pub const ListProducerFramePlan = struct {
    phase: ListProducerFramePhase,
    callback: ListProducerCallbackState,
    sink_future: ListProducerFutureState,
    queue_occupied: bool,
    list_live: bool,
    source_slots_live: bool,
    source_slots_transferred: bool,
    waitable_registered: bool,
    writer_live: bool,
    actions: std.ArrayList(ListProducerFrameAction),
    terminal_done: bool,

    pub fn init(allocator: std.mem.Allocator) ListProducerFramePlan {
        _ = allocator;
        return .{
            .phase = .empty,
            .callback = .none,
            .sink_future = .none,
            .queue_occupied = false,
            .list_live = false,
            .source_slots_live = false,
            .source_slots_transferred = false,
            .waitable_registered = false,
            .writer_live = true,
            .actions = .empty,
            .terminal_done = false,
        };
    }

    pub fn deinit(self: *ListProducerFramePlan, allocator: std.mem.Allocator) void {
        self.actions.deinit(allocator);
    }

    pub fn apply(self: *ListProducerFramePlan, operation: ListProducerFrameOperation, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.terminal_done) return error.TerminalAlreadyConsumed;
        switch (operation) {
            .allocate => try self.allocate(allocator),
            .queue => try self.queue(allocator),
            .transfer => try self.transfer(allocator),
            .await_sink => try self.await_sink(allocator),
            .complete => |callback| try self.complete(allocator, callback),
            .cancel => try self.cancel(allocator),
            .early_drop => try self.early_drop(allocator),
            .finalize => try self.finalize(allocator),
        }
    }

    fn allocate(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase != .empty) return error.InvalidTransition;
        self.phase = .allocated;
        self.list_live = true;
        self.source_slots_live = true;
        try self.actions.append(allocator, .{ .kind = .allocate_list });
    }

    fn queue(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase == .queued or self.queue_occupied) return error.SecondQueueItem;
        if (self.phase != .allocated or !self.list_live) return error.InvalidTransition;
        self.phase = .queued;
        self.queue_occupied = true;
        try self.actions.append(allocator, .{ .kind = .queue });
    }

    fn transfer(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase != .queued or !self.queue_occupied) return error.InvalidTransition;
        self.phase = .transferred;
        self.queue_occupied = false;
        self.source_slots_transferred = true;
        try self.actions.append(allocator, .{ .kind = .transfer });
    }

    fn await_sink(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase != .transferred or !self.list_live) return error.InvalidTransition;
        self.phase = .awaiting;
        self.callback = .pending;
        self.sink_future = .pending;
        self.waitable_registered = true;
        try self.actions.append(allocator, .{ .kind = .register_waitable });
        try self.actions.append(allocator, .{ .kind = .await_sink });
    }

    fn complete(self: *ListProducerFramePlan, allocator: std.mem.Allocator, callback: ListProducerCallbackState) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase != .awaiting or self.callback != .pending) return error.InvalidTransition;
        if (callback != .ready and callback != .failed) return error.InvalidTransition;
        self.phase = .completed;
        self.callback = callback;
        self.sink_future = if (callback == .ready) .ready else .failed;
        try self.actions.append(allocator, .{ .kind = if (callback == .ready) .callback_ready else .callback_error });
    }

    fn cancel(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase == .completed or self.phase == .cancelled or self.phase == .dropped or self.phase == .finalized) {
            return error.TerminalAlreadyConsumed;
        }
        if (self.phase == .empty) return error.InvalidTransition;
        self.phase = .cancelled;
        self.queue_occupied = false;
        self.callback = .cancelled;
        try self.actions.append(allocator, .{ .kind = .callback_cancel });
        try self.cleanup_children(allocator);
        try self.finish_terminal(allocator);
    }

    fn early_drop(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase == .completed or self.phase == .cancelled or self.phase == .dropped or self.phase == .finalized) {
            return error.TerminalAlreadyConsumed;
        }
        if (self.phase == .empty) return error.InvalidTransition;
        self.phase = .dropped;
        self.queue_occupied = false;
        self.callback = .dropped;
        try self.actions.append(allocator, .{ .kind = .callback_drop });
        try self.cleanup_children(allocator);
        try self.finish_terminal(allocator);
    }

    fn finalize(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.phase != .completed) {
            if (self.phase == .cancelled or self.phase == .dropped or self.phase == .finalized) return error.TerminalAlreadyConsumed;
            return error.InvalidTransition;
        }
        try self.cleanup_children(allocator);
        self.phase = .finalized;
        try self.finish_terminal(allocator);
    }

    fn cleanup_children(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.list_live) {
            if (self.source_slots_transferred and self.source_slots_live) {
                try self.actions.append(allocator, .{ .kind = .clear_source_slots });
            }
            self.source_slots_live = false;
            try self.actions.append(allocator, .{ .kind = .release_list });
            self.list_live = false;
        }
        if (self.sink_future != .none and self.sink_future != .dropped) {
            self.sink_future = .dropped;
            try self.actions.append(allocator, .{ .kind = .drop_sink_future });
        }
        if (self.waitable_registered) {
            self.waitable_registered = false;
            try self.actions.append(allocator, .{ .kind = .unregister_waitable });
        }
    }

    fn finish_terminal(self: *ListProducerFramePlan, allocator: std.mem.Allocator) (AsyncError || std.mem.Allocator.Error)!void {
        if (self.writer_live) {
            self.writer_live = false;
            try self.actions.append(allocator, .{ .kind = .drop_stream_writer });
        }
        try self.actions.append(allocator, .{ .kind = .drop_frame });
        try self.actions.append(allocator, .{ .kind = .terminal_finalize });
        self.terminal_done = true;
    }
};

pub fn build(
    allocator: std.mem.Allocator,
    specs: []const EndpointSpec,
    events: []const Event,
) (AsyncError || std.mem.Allocator.Error)!AsyncPlan {
    var endpoints = std.ArrayList(EndpointStatus).empty;
    errdefer endpoints.deinit(allocator);
    var actions = std.ArrayList(AsyncAction).empty;
    errdefer actions.deinit(allocator);

    for (specs, 0..) |spec, index| {
        if (spec.name.len == 0) return error.InvalidEndpoint;
        for (specs[0..index]) |previous| {
            if (std.mem.eql(u8, previous.name, spec.name)) return error.DuplicateEndpoint;
        }
        try endpoints.append(allocator, .{
            .name = spec.name,
            .kind = spec.kind,
            .parent = spec.parent,
            .owner_open = spec.owns_resource,
        });
    }
    for (endpoints.items) |endpoint| {
        if (endpoint.parent) |parent| {
            if (find_endpoint(endpoints.items, parent) == null) return error.UnknownEndpoint;
        }
    }

    for (events) |event| try apply_event(endpoints.items, allocator, &actions, event);
    for (endpoints.items) |endpoint| {
        if (endpoint.owner_open) return error.UnclosedOwner;
        if (endpoint.state == .pending or endpoint.state == .ready or endpoint.state == .failed) {
            return error.UnfinishedEndpoint;
        }
    }

    const owned_actions = try actions.toOwnedSlice(allocator);
    errdefer allocator.free(owned_actions);
    const owned_endpoints = try endpoints.toOwnedSlice(allocator);
    return .{
        .actions = owned_actions,
        .endpoints = owned_endpoints,
    };
}

fn apply_event(
    endpoints: []EndpointStatus,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(AsyncAction),
    event: Event,
) (AsyncError || std.mem.Allocator.Error)!void {
    switch (event) {
        .poll => |value| {
            const endpoint = find_endpoint_mut(endpoints, value.name) orelse return error.UnknownEndpoint;
            if (endpoint.state != .pending) return error.PollAfterTerminal;
            try actions.append(allocator, .{ .kind = .poll, .name = value.name });
        },
        .ready => |value| {
            const endpoint = find_endpoint_mut(endpoints, value.name) orelse return error.UnknownEndpoint;
            if (endpoint.state != .pending) return error.InvalidTransition;
            endpoint.state = .ready;
            try actions.append(allocator, .{ .kind = .ready, .name = value.name });
        },
        .completion_error => |value| {
            const endpoint = find_endpoint_mut(endpoints, value.name) orelse return error.UnknownEndpoint;
            if (endpoint.state != .pending) return error.InvalidTransition;
            endpoint.state = .failed;
            try actions.append(allocator, .{ .kind = .completion_error, .name = value.name });
        },
        .cancel => |value| try apply_cancel(endpoints, allocator, actions, value.name),
        .consume => |value| try apply_consume(endpoints, allocator, actions, value.name),
        .drop => |value| try apply_drop(endpoints, allocator, actions, value.name),
        .close_owner => |value| try apply_close_owner(endpoints, allocator, actions, value.name),
    }
}

fn apply_cancel(
    endpoints: []EndpointStatus,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(AsyncAction),
    name: []const u8,
) (AsyncError || std.mem.Allocator.Error)!void {
    const endpoint = find_endpoint_mut(endpoints, name) orelse return error.UnknownEndpoint;
    switch (endpoint.state) {
        .pending => {
            endpoint.state = .cancelled;
            try actions.append(allocator, .{ .kind = .cancel, .name = name });
            try cleanup_endpoint(endpoint, allocator, actions, name);
        },
        .cancelled => return error.DoubleCancellation,
        else => return error.TerminalAlreadyConsumed,
    }
}

fn apply_consume(
    endpoints: []EndpointStatus,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(AsyncAction),
    name: []const u8,
) (AsyncError || std.mem.Allocator.Error)!void {
    const endpoint = find_endpoint_mut(endpoints, name) orelse return error.UnknownEndpoint;
    if (endpoint.state != .ready and endpoint.state != .failed) return error.TerminalAlreadyConsumed;
    endpoint.state = .consumed;
    try actions.append(allocator, .{ .kind = .consume, .name = name });
    try cleanup_endpoint(endpoint, allocator, actions, name);
}

fn apply_drop(
    endpoints: []EndpointStatus,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(AsyncAction),
    name: []const u8,
) (AsyncError || std.mem.Allocator.Error)!void {
    const endpoint = find_endpoint_mut(endpoints, name) orelse return error.UnknownEndpoint;
    if (endpoint.parent) |parent_name| {
        const parent = find_endpoint(endpoints, parent_name) orelse return error.UnknownEndpoint;
        if (!is_dependency_terminal(parent.state)) return error.ChildBeforeParent;
    }
    if (endpoint.state != .pending and endpoint.state != .ready and endpoint.state != .failed) {
        return error.TerminalAlreadyConsumed;
    }
    endpoint.state = .dropped;
    try actions.append(allocator, .{ .kind = .drop, .name = name });
    try cleanup_endpoint(endpoint, allocator, actions, name);
}

fn apply_close_owner(
    endpoints: []EndpointStatus,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(AsyncAction),
    name: []const u8,
) (AsyncError || std.mem.Allocator.Error)!void {
    const endpoint = find_endpoint_mut(endpoints, name) orelse return error.UnknownEndpoint;
    if (!endpoint.owner_open) return error.InvalidTransition;
    if (!is_dependency_terminal(endpoint.state)) return error.OwnerStillActive;
    endpoint.owner_open = false;
    endpoint.state = .closed;
    endpoint.cleanup_count += 1;
    try actions.append(allocator, .{ .kind = .close_owner, .name = name });
}

fn cleanup_endpoint(
    endpoint: *EndpointStatus,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(AsyncAction),
    name: []const u8,
) (AsyncError || std.mem.Allocator.Error)!void {
    if (endpoint.endpoint_cleaned) return error.DoubleCleanup;
    endpoint.endpoint_cleaned = true;
    endpoint.cleanup_count += 1;
    try actions.append(allocator, .{ .kind = .cleanup, .name = name });
}

fn is_dependency_terminal(state: AsyncState) bool {
    return state == .consumed or state == .cancelled or state == .dropped or state == .closed;
}

fn find_endpoint(endpoints: []const EndpointStatus, name: []const u8) ?EndpointStatus {
    for (endpoints) |endpoint| if (std.mem.eql(u8, endpoint.name, name)) return endpoint;
    return null;
}

fn find_endpoint_mut(endpoints: []EndpointStatus, name: []const u8) ?*EndpointStatus {
    for (endpoints) |*endpoint| if (std.mem.eql(u8, endpoint.name, name)) return endpoint;
    return null;
}

test "pending future reaches ready and is cleaned exactly once on consume" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future }};
    const events = [_]Event{
        .{ .poll = .{ .name = "future" } },
        .{ .ready = .{ .name = "future" } },
        .{ .consume = .{ .name = "future" } },
    };
    var plan = try build(std.testing.allocator, &endpoints, &events);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(AsyncState.consumed, plan.state("future").?);
    try std.testing.expectEqual(@as(u32, 1), plan.cleanup_count("future").?);
}

test "future may become ready without a pending poll" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future }};
    const events = [_]Event{
        .{ .ready = .{ .name = "future" } },
        .{ .consume = .{ .name = "future" } },
    };
    var plan = try build(std.testing.allocator, &endpoints, &events);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(AsyncState.consumed, plan.state("future").?);
}

test "completion error is a terminal result that can be consumed" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future }};
    const events = [_]Event{
        .{ .completion_error = .{ .name = "future" } },
        .{ .consume = .{ .name = "future" } },
    };
    var plan = try build(std.testing.allocator, &endpoints, &events);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(AsyncState.consumed, plan.state("future").?);
    try std.testing.expectEqual(@as(u32, 1), plan.cleanup_count("future").?);
}

test "explicit cancellation is terminal and cleans once" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future }};
    const events = [_]Event{.{ .cancel = .{ .name = "future" } }};
    var plan = try build(std.testing.allocator, &endpoints, &events);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(AsyncState.cancelled, plan.state("future").?);
    try std.testing.expectEqual(@as(u32, 1), plan.cleanup_count("future").?);
}

test "early drop cleans a pending endpoint" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future }};
    const events = [_]Event{.{ .drop = .{ .name = "future" } }};
    var plan = try build(std.testing.allocator, &endpoints, &events);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(AsyncState.dropped, plan.state("future").?);
    try std.testing.expectEqual(@as(u32, 1), plan.cleanup_count("future").?);
}

test "polling after terminal consumption is rejected" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future }};
    const events = [_]Event{
        .{ .ready = .{ .name = "future" } },
        .{ .consume = .{ .name = "future" } },
        .{ .poll = .{ .name = "future" } },
    };
    try std.testing.expectError(error.PollAfterTerminal, build(std.testing.allocator, &endpoints, &events));
}

test "double cancellation is rejected" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future }};
    const events = [_]Event{
        .{ .cancel = .{ .name = "future" } },
        .{ .cancel = .{ .name = "future" } },
    };
    try std.testing.expectError(error.DoubleCancellation, build(std.testing.allocator, &endpoints, &events));
}

test "child cannot drop before its parent dependency is terminal" {
    const endpoints = [_]EndpointSpec{
        .{ .name = "parent", .kind = .future },
        .{ .name = "child", .kind = .stream, .parent = "parent" },
    };
    const events = [_]Event{.{ .drop = .{ .name = "child" } }};
    try std.testing.expectError(error.ChildBeforeParent, build(std.testing.allocator, &endpoints, &events));
}

test "owned async endpoint must close its owner before finalization" {
    const endpoints = [_]EndpointSpec{.{ .name = "future", .kind = .future, .owns_resource = true }};
    const events = [_]Event{
        .{ .ready = .{ .name = "future" } },
        .{ .consume = .{ .name = "future" } },
    };
    try std.testing.expectError(error.UnclosedOwner, build(std.testing.allocator, &endpoints, &events));

    const closed_events = [_]Event{
        .{ .ready = .{ .name = "future" } },
        .{ .consume = .{ .name = "future" } },
        .{ .close_owner = .{ .name = "future" } },
    };
    var plan = try build(std.testing.allocator, &endpoints, &closed_events);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 2), plan.cleanup_count("future").?);
}

test "list producer frame follows allocate queue transfer await finalize" {
    var plan = ListProducerFramePlan.init(std.testing.allocator);
    defer plan.deinit(std.testing.allocator);
    try plan.apply(.{ .allocate = {} }, std.testing.allocator);
    try plan.apply(.{ .queue = {} }, std.testing.allocator);
    try std.testing.expectError(error.SecondQueueItem, plan.apply(.{ .queue = {} }, std.testing.allocator));
    try plan.apply(.{ .transfer = {} }, std.testing.allocator);
    try plan.apply(.{ .await_sink = {} }, std.testing.allocator);
    try plan.apply(.{ .complete = .ready }, std.testing.allocator);
    try plan.apply(.{ .finalize = {} }, std.testing.allocator);

    try std.testing.expectEqual(ListProducerFramePhase.finalized, plan.phase);
    try std.testing.expectEqual(ListProducerCallbackState.ready, plan.callback);
    try std.testing.expect(!plan.waitable_registered);
    try std.testing.expect(!plan.writer_live);
    try std.testing.expectEqual(ListProducerFutureState.dropped, plan.sink_future);
    try std.testing.expectEqual(@as(usize, 13), plan.actions.items.len);
    try std.testing.expectEqual(ListProducerFrameActionKind.clear_source_slots, plan.actions.items[6].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.release_list, plan.actions.items[7].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.drop_sink_future, plan.actions.items[8].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.unregister_waitable, plan.actions.items[9].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.drop_frame, plan.actions.items[11].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.terminal_finalize, plan.actions.items[12].kind);
}

test "list producer frame cancellation before transfer cleans queued state" {
    var plan = ListProducerFramePlan.init(std.testing.allocator);
    defer plan.deinit(std.testing.allocator);
    try plan.apply(.{ .allocate = {} }, std.testing.allocator);
    try plan.apply(.{ .queue = {} }, std.testing.allocator);
    try plan.apply(.{ .cancel = {} }, std.testing.allocator);
    try std.testing.expectEqual(ListProducerFramePhase.cancelled, plan.phase);
    try std.testing.expect(!plan.queue_occupied);
    try std.testing.expect(!plan.list_live);
    try std.testing.expectEqual(ListProducerFrameActionKind.release_list, plan.actions.items[3].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.drop_frame, plan.actions.items[5].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.terminal_finalize, plan.actions.items[6].kind);
}

test "list producer frame cancellation after transfer clears list before dropping future" {
    var plan = ListProducerFramePlan.init(std.testing.allocator);
    defer plan.deinit(std.testing.allocator);
    try plan.apply(.{ .allocate = {} }, std.testing.allocator);
    try plan.apply(.{ .queue = {} }, std.testing.allocator);
    try plan.apply(.{ .transfer = {} }, std.testing.allocator);
    try plan.apply(.{ .await_sink = {} }, std.testing.allocator);
    try plan.apply(.{ .cancel = {} }, std.testing.allocator);
    try std.testing.expectEqual(ListProducerFramePhase.cancelled, plan.phase);
    try std.testing.expect(!plan.source_slots_live);
    try std.testing.expectEqual(ListProducerCallbackState.cancelled, plan.callback);
    for (plan.actions.items) |action| try std.testing.expect(action.kind != .callback_ready);
    try std.testing.expectEqual(ListProducerFrameActionKind.clear_source_slots, plan.actions.items[6].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.release_list, plan.actions.items[7].kind);
    try std.testing.expectEqual(ListProducerFrameActionKind.drop_sink_future, plan.actions.items[8].kind);
}

test "list producer frame early drop and invalid terminal transitions are guarded" {
    var plan = ListProducerFramePlan.init(std.testing.allocator);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidTransition, plan.apply(.{ .transfer = {} }, std.testing.allocator));
    try plan.apply(.{ .allocate = {} }, std.testing.allocator);
    try plan.apply(.{ .early_drop = {} }, std.testing.allocator);
    try std.testing.expectEqual(ListProducerFramePhase.dropped, plan.phase);
    try std.testing.expectEqual(ListProducerCallbackState.dropped, plan.callback);
    try std.testing.expectError(error.TerminalAlreadyConsumed, plan.apply(.{ .finalize = {} }, std.testing.allocator));
    try std.testing.expectError(error.TerminalAlreadyConsumed, plan.apply(.{ .early_drop = {} }, std.testing.allocator));
}
