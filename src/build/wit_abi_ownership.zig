const std = @import("std");
const abi_types = @import("wit_abi_types.zig");

pub const OwnershipError = error{
    InvalidBinding,
    DuplicateBinding,
    UnknownBinding,
    InvalidOperation,
    OwnTransferFromBorrow,
    UseAfterMove,
    DuplicateRelease,
    BorrowEscapesCall,
    ActiveBorrow,
    BranchOwnershipMismatch,
    InvalidProducerCardinality,
    InvalidProducerState,
    ProducerQueueFull,
    TransferredRelease,
    SlotAlreadyCleared,
    TerminalFinalized,
};

pub const OwnershipState = enum {
    owned,
    moved,
    released,
    maybe,
};

pub const ResourceBinding = struct {
    name: []const u8,
    abi_type: *const abi_types.AbiType,
    mode: abi_types.ResourceMode,

    pub fn init(name: []const u8, abi_type: *const abi_types.AbiType) OwnershipError!ResourceBinding {
        if (name.len == 0 or abi_type.kind() != .resource) return error.InvalidBinding;
        const mode = abi_type.resource_mode() orelse return error.InvalidBinding;
        return .{ .name = name, .abi_type = abi_type, .mode = mode };
    }
};

pub const ActionKind = enum {
    move,
    borrow,
    clear,
    release,
    early_drop,
};

pub const OwnershipAction = struct {
    kind: ActionKind,
    source: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    owner: ?[]const u8 = null,
    call: ?[]const u8 = null,
};

pub const OwnershipPlan = struct {
    actions: []OwnershipAction,

    pub fn deinit(self: *OwnershipPlan, allocator: std.mem.Allocator) void {
        if (self.actions.len != 0) allocator.free(self.actions);
        self.actions = &.{};
    }
};

pub const ListProducerState = enum {
    unallocated,
    guest_owned,
    queued,
    transferred,
    finalized,
    maybe,
};

pub const ListProducerStateEntry = struct {
    name: []const u8,
    state: ListProducerState,
};

pub const ListProducerActionKind = enum {
    allocate_list,
    create_ticket,
    enqueue,
    transfer,
    clear_source_slot,
    release_ticket,
    release_list,
    drop_stream,
    drop_future,
    drop_frame,
    terminal_finalize,
};

pub const ListProducerAction = struct {
    kind: ListProducerActionKind,
    index: ?u32 = null,
};

pub const ListProducerOperation = union(enum) {
    allocate: void,
    create_ticket: u32,
    enqueue: void,
    transfer: void,
    clear_source_slot: u32,
    release_ticket: u32,
    release_list: void,
    cancel: void,
    terminal_finalize: void,
};

pub const ListProducerOwnershipPlan = struct {
    allocator: std.mem.Allocator,
    length: u32,
    capacity: u32,
    admitted_lengths: []u32,
    list_state: ListProducerState,
    ticket_states: []ListProducerState,
    source_slots_cleared: []bool,
    actions: std.ArrayList(ListProducerAction),
    stream_started: bool,
    terminal_done: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        length: u32,
        capacity: u32,
        admitted_lengths: []const u32,
    ) (OwnershipError || std.mem.Allocator.Error)!ListProducerOwnershipPlan {
        if (capacity == 0 or length > capacity) return error.InvalidProducerCardinality;
        try validate_admitted_lengths(capacity, admitted_lengths);
        if (!is_admitted_length(length, admitted_lengths)) return error.InvalidProducerCardinality;

        const copied_lengths = try allocator.dupe(u32, admitted_lengths);
        errdefer allocator.free(copied_lengths);
        const ticket_states = try allocator.alloc(ListProducerState, length);
        errdefer allocator.free(ticket_states);
        @memset(ticket_states, .unallocated);
        const source_slots_cleared = try allocator.alloc(bool, length);
        errdefer allocator.free(source_slots_cleared);
        @memset(source_slots_cleared, false);
        return .{
            .allocator = allocator,
            .length = length,
            .capacity = capacity,
            .admitted_lengths = copied_lengths,
            .list_state = .unallocated,
            .ticket_states = ticket_states,
            .source_slots_cleared = source_slots_cleared,
            .actions = .empty,
            .stream_started = false,
            .terminal_done = false,
        };
    }

    pub fn deinit(self: *ListProducerOwnershipPlan) void {
        self.actions.deinit(self.allocator);
        if (self.admitted_lengths.len != 0) self.allocator.free(self.admitted_lengths);
        if (self.ticket_states.len != 0) self.allocator.free(self.ticket_states);
        if (self.source_slots_cleared.len != 0) self.allocator.free(self.source_slots_cleared);
        self.admitted_lengths = &.{};
        self.ticket_states = &.{};
        self.source_slots_cleared = &.{};
    }

    pub fn apply(self: *ListProducerOwnershipPlan, operation: ListProducerOperation) (OwnershipError || std.mem.Allocator.Error)!void {
        if (self.terminal_done) return error.TerminalFinalized;
        switch (operation) {
            .allocate => try self.allocate_list(),
            .create_ticket => |index| try self.create_ticket(index),
            .enqueue => try self.enqueue_item(),
            .transfer => try self.transfer_item(),
            .clear_source_slot => |index| try self.clear_source_slot(index),
            .release_ticket => |index| try self.release_ticket(index),
            .release_list => try self.release_list(),
            .cancel => try self.cancel(),
            .terminal_finalize => try self.terminal_finalize(),
        }
    }

    fn allocate_list(self: *ListProducerOwnershipPlan) (OwnershipError || std.mem.Allocator.Error)!void {
        if (self.list_state != .unallocated) return error.InvalidProducerState;
        self.list_state = .guest_owned;
        try self.actions.append(self.allocator, .{ .kind = .allocate_list });
    }

    fn create_ticket(self: *ListProducerOwnershipPlan, index: u32) (OwnershipError || std.mem.Allocator.Error)!void {
        if (self.list_state != .guest_owned or index >= self.length) return error.InvalidProducerState;
        const state = &self.ticket_states[index];
        if (state.* != .unallocated) return error.InvalidProducerState;
        state.* = .guest_owned;
        try self.actions.append(self.allocator, .{ .kind = .create_ticket, .index = index });
    }

    fn enqueue_item(self: *ListProducerOwnershipPlan) (OwnershipError || std.mem.Allocator.Error)!void {
        if (self.list_state == .queued) return error.ProducerQueueFull;
        if (self.list_state != .guest_owned) return error.InvalidProducerState;
        for (self.ticket_states) |state| if (state != .guest_owned) return error.InvalidProducerState;
        self.list_state = .queued;
        self.stream_started = true;
        try self.actions.append(self.allocator, .{ .kind = .enqueue });
    }

    fn transfer_item(self: *ListProducerOwnershipPlan) (OwnershipError || std.mem.Allocator.Error)!void {
        if (self.list_state != .queued) return error.InvalidProducerState;
        for (self.ticket_states) |*state| {
            if (state.* != .guest_owned) return error.InvalidProducerState;
            state.* = .transferred;
        }
        self.list_state = .transferred;
        try self.actions.append(self.allocator, .{ .kind = .transfer });
    }

    fn clear_source_slot(self: *ListProducerOwnershipPlan, index: u32) (OwnershipError || std.mem.Allocator.Error)!void {
        if (self.list_state != .transferred or index >= self.length) return error.InvalidProducerState;
        if (self.ticket_states[index] != .transferred) return error.InvalidProducerState;
        if (self.source_slots_cleared[index]) return error.SlotAlreadyCleared;
        self.source_slots_cleared[index] = true;
        try self.actions.append(self.allocator, .{ .kind = .clear_source_slot, .index = index });
    }

    fn release_ticket(self: *ListProducerOwnershipPlan, index: u32) (OwnershipError || std.mem.Allocator.Error)!void {
        if (index >= self.length) return error.InvalidProducerState;
        switch (self.ticket_states[index]) {
            .guest_owned => self.ticket_states[index] = .finalized,
            .transferred => return error.TransferredRelease,
            .finalized => return error.DuplicateRelease,
            else => return error.InvalidProducerState,
        }
        try self.actions.append(self.allocator, .{ .kind = .release_ticket, .index = index });
    }

    fn release_list(self: *ListProducerOwnershipPlan) (OwnershipError || std.mem.Allocator.Error)!void {
        switch (self.list_state) {
            .guest_owned, .queued => {
                for (self.ticket_states) |state| if (state == .guest_owned) return error.InvalidProducerState;
            },
            .transferred => {
                for (self.ticket_states, self.source_slots_cleared) |state, cleared| {
                    if (state == .transferred and !cleared) return error.InvalidProducerState;
                }
            },
            .finalized => return error.DuplicateRelease,
            else => return error.InvalidProducerState,
        }
        self.list_state = .finalized;
        try self.actions.append(self.allocator, .{ .kind = .release_list });
    }

    fn cancel(self: *ListProducerOwnershipPlan) (OwnershipError || std.mem.Allocator.Error)!void {
        switch (self.list_state) {
            .unallocated => self.list_state = .finalized,
            .guest_owned, .queued => {
                for (self.ticket_states, 0..) |state, index| {
                    if (state == .guest_owned) try self.release_ticket(@intCast(index));
                }
                try self.release_list();
            },
            .transferred => {
                for (self.ticket_states, 0..) |state, index| {
                    if (state == .transferred and !self.source_slots_cleared[index]) {
                        try self.clear_source_slot(@intCast(index));
                    }
                }
                try self.release_list();
            },
            .finalized => return error.InvalidProducerState,
            .maybe => return error.BranchOwnershipMismatch,
        }
        try self.terminal_finalize();
    }

    fn terminal_finalize(self: *ListProducerOwnershipPlan) (OwnershipError || std.mem.Allocator.Error)!void {
        if (self.list_state != .finalized) return error.InvalidProducerState;
        if (self.stream_started) {
            try self.actions.append(self.allocator, .{ .kind = .drop_stream });
            try self.actions.append(self.allocator, .{ .kind = .drop_future });
        }
        try self.actions.append(self.allocator, .{ .kind = .drop_frame });
        try self.actions.append(self.allocator, .{ .kind = .terminal_finalize });
        self.terminal_done = true;
    }
};

pub fn join_list_producer_states(
    allocator: std.mem.Allocator,
    branches: []const []const ListProducerStateEntry,
) (OwnershipError || std.mem.Allocator.Error)![]ListProducerStateEntry {
    if (branches.len == 0) return error.BranchOwnershipMismatch;
    const first = branches[0];
    for (first) |entry| if (entry.state == .maybe) return error.BranchOwnershipMismatch;
    for (branches[1..]) |branch| {
        if (branch.len != first.len) return error.BranchOwnershipMismatch;
        for (first, branch) |expected, actual| {
            if (expected.state == .maybe or actual.state == .maybe or
                !std.mem.eql(u8, expected.name, actual.name) or expected.state != actual.state)
            {
                return error.BranchOwnershipMismatch;
            }
        }
    }
    return try allocator.dupe(ListProducerStateEntry, first);
}

fn validate_admitted_lengths(capacity: u32, lengths: []const u32) OwnershipError!void {
    if (lengths.len == 0 or lengths[0] != 0) return error.InvalidProducerCardinality;
    var previous: u32 = 0;
    for (lengths, 0..) |length, index| {
        if (length > capacity or (index != 0 and length <= previous)) return error.InvalidProducerCardinality;
        previous = length;
    }
}

fn is_admitted_length(length: u32, admitted_lengths: []const u32) bool {
    for (admitted_lengths) |admitted| if (admitted == length) return true;
    return false;
}

pub const MoveOperation = struct {
    source: []const u8,
    destination: []const u8,
};

pub const BorrowOperation = struct {
    owner: []const u8,
    call: []const u8,
};

pub const EndCallOperation = struct {
    call: []const u8,
};

pub const NameOperation = struct {
    name: []const u8,
};

pub const BorrowEscapeOperation = struct {
    owner: []const u8,
    call: []const u8,
    destination: []const u8,
};

pub const Operation = union(enum) {
    move: MoveOperation,
    borrow: BorrowOperation,
    end_call: EndCallOperation,
    release: NameOperation,
    clear: NameOperation,
    early_drop: NameOperation,
    borrow_escape: BorrowEscapeOperation,
};

pub const StateEntry = struct {
    name: []const u8,
    state: OwnershipState,
};

const BindingState = struct {
    name: []const u8,
    mode: abi_types.ResourceMode,
    state: OwnershipState,
    active_call: ?[]const u8 = null,
};

pub fn build(
    allocator: std.mem.Allocator,
    bindings: []const ResourceBinding,
    operations: []const Operation,
) (OwnershipError || std.mem.Allocator.Error)!OwnershipPlan {
    var states = std.ArrayList(BindingState).empty;
    defer states.deinit(allocator);
    var actions = std.ArrayList(OwnershipAction).empty;
    errdefer actions.deinit(allocator);

    for (bindings, 0..) |binding, index| {
        if (binding.name.len == 0 or binding.abi_type.kind() != .resource) return error.InvalidBinding;
        const actual_mode = binding.abi_type.resource_mode() orelse return error.InvalidBinding;
        if (actual_mode != binding.mode) return error.InvalidBinding;
        for (bindings[0..index]) |previous| {
            if (std.mem.eql(u8, previous.name, binding.name)) return error.DuplicateBinding;
        }
        try states.append(allocator, .{
            .name = binding.name,
            .mode = binding.mode,
            .state = .owned,
        });
    }

    for (operations) |operation| {
        switch (operation) {
            .move => |value| try apply_move(&states, allocator, &actions, value),
            .borrow => |value| try apply_borrow(&states, allocator, &actions, value),
            .end_call => |value| try apply_end_call(states.items, value),
            .release => |value| try apply_release(states.items, allocator, &actions, value),
            .clear => |value| try apply_clear(states.items, allocator, &actions, value),
            .early_drop => |value| try apply_early_drop(states.items, allocator, &actions, value),
            .borrow_escape => |value| try apply_borrow_escape(states.items, value),
        }
    }

    return .{ .actions = try actions.toOwnedSlice(allocator) };
}

pub fn join_states(
    allocator: std.mem.Allocator,
    branches: []const []const StateEntry,
) (OwnershipError || std.mem.Allocator.Error)![]StateEntry {
    if (branches.len == 0) return error.BranchOwnershipMismatch;
    const first = branches[0];
    for (first) |entry| if (entry.state == .maybe) return error.BranchOwnershipMismatch;
    for (branches[1..]) |branch| {
        if (branch.len != first.len) return error.BranchOwnershipMismatch;
        for (first, branch) |expected, actual| {
            if (expected.state == .maybe or actual.state == .maybe or
                !std.mem.eql(u8, expected.name, actual.name) or expected.state != actual.state)
            {
                return error.BranchOwnershipMismatch;
            }
        }
    }
    return try allocator.dupe(StateEntry, first);
}

fn apply_move(
    states: *std.ArrayList(BindingState),
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(OwnershipAction),
    value: MoveOperation,
) (OwnershipError || std.mem.Allocator.Error)!void {
    if (find_state(states.items, value.destination) != null) return error.DuplicateBinding;
    const source = find_state_mut(states.items, value.source) orelse return error.UnknownBinding;
    if (source.mode != .own) return error.OwnTransferFromBorrow;
    if (source.active_call != null) return error.ActiveBorrow;
    if (source.state != .owned) return error.UseAfterMove;

    source.state = .moved;
    try actions.append(allocator, .{
        .kind = .move,
        .source = value.source,
        .destination = value.destination,
    });
    try actions.append(allocator, .{ .kind = .clear, .source = value.source });
    try states.append(allocator, .{
        .name = value.destination,
        .mode = .own,
        .state = .owned,
    });
}

fn apply_borrow(
    states: *std.ArrayList(BindingState),
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(OwnershipAction),
    value: BorrowOperation,
) (OwnershipError || std.mem.Allocator.Error)!void {
    const owner = find_state_mut(states.items, value.owner) orelse return error.UnknownBinding;
    if (value.call.len == 0 or owner.mode != .own) return error.InvalidOperation;
    if (owner.state != .owned) return error.UseAfterMove;
    if (owner.active_call != null) return error.ActiveBorrow;
    owner.active_call = value.call;
    try actions.append(allocator, .{
        .kind = .borrow,
        .owner = value.owner,
        .call = value.call,
    });
}

fn apply_end_call(states: []BindingState, value: EndCallOperation) OwnershipError!void {
    if (value.call.len == 0) return error.InvalidOperation;
    var found = false;
    for (states) |*state| {
        if (state.active_call) |call| {
            if (!std.mem.eql(u8, call, value.call)) continue;
            state.active_call = null;
            found = true;
        }
    }
    if (!found) return error.InvalidOperation;
}

fn apply_release(
    states: []BindingState,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(OwnershipAction),
    value: NameOperation,
) (OwnershipError || std.mem.Allocator.Error)!void {
    const state = find_state_mut(states, value.name) orelse return error.UnknownBinding;
    if (state.mode != .own) return error.InvalidOperation;
    if (state.active_call != null) return error.ActiveBorrow;
    switch (state.state) {
        .released => return error.DuplicateRelease,
        .moved => return error.UseAfterMove,
        .owned => {},
        .maybe => return error.BranchOwnershipMismatch,
    }
    state.state = .released;
    try actions.append(allocator, .{ .kind = .release, .owner = value.name });
}

fn apply_clear(
    states: []BindingState,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(OwnershipAction),
    value: NameOperation,
) (OwnershipError || std.mem.Allocator.Error)!void {
    const state = find_state(states, value.name) orelse return error.UnknownBinding;
    if (state.state == .owned) return error.InvalidOperation;
    try actions.append(allocator, .{ .kind = .clear, .source = value.name });
}

fn apply_early_drop(
    states: []BindingState,
    allocator: std.mem.Allocator,
    actions: *std.ArrayList(OwnershipAction),
    value: NameOperation,
) (OwnershipError || std.mem.Allocator.Error)!void {
    const state = find_state_mut(states, value.name) orelse return error.UnknownBinding;
    if (state.mode != .own) return error.InvalidOperation;
    if (state.active_call != null) return error.ActiveBorrow;
    switch (state.state) {
        .released => return error.DuplicateRelease,
        .moved => return error.UseAfterMove,
        .owned => {},
        .maybe => return error.BranchOwnershipMismatch,
    }
    state.state = .released;
    try actions.append(allocator, .{ .kind = .early_drop, .owner = value.name });
    try actions.append(allocator, .{ .kind = .clear, .source = value.name });
}

fn apply_borrow_escape(states: []BindingState, value: BorrowEscapeOperation) OwnershipError!void {
    const owner = find_state(states, value.owner) orelse return error.UnknownBinding;
    if (owner.state != .owned or value.call.len == 0 or value.destination.len == 0) return error.InvalidOperation;
    return error.BorrowEscapesCall;
}

fn find_state(states: []const BindingState, name: []const u8) ?BindingState {
    for (states) |state| if (std.mem.eql(u8, state.name, name)) return state;
    return null;
}

fn find_state_mut(states: []BindingState, name: []const u8) ?*BindingState {
    for (states) |*state| if (std.mem.eql(u8, state.name, name)) return state;
    return null;
}

test "own transfer has one release authority and clears the source" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    const bindings = [_]ResourceBinding{try ResourceBinding.init("ticket", &ticket)};
    const operations = [_]Operation{
        .{ .move = .{ .source = "ticket", .destination = "sent" } },
        .{ .release = .{ .name = "sent" } },
    };

    var plan = try build(std.testing.allocator, &bindings, &operations);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), plan.actions.len);
    try std.testing.expectEqual(ActionKind.move, plan.actions[0].kind);
    try std.testing.expectEqual(ActionKind.clear, plan.actions[1].kind);
    try std.testing.expectEqual(ActionKind.release, plan.actions[2].kind);
}

test "direct borrow retains the owner and emits no borrow release" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    const bindings = [_]ResourceBinding{try ResourceBinding.init("ticket", &ticket)};
    const operations = [_]Operation{
        .{ .borrow = .{ .owner = "ticket", .call = "read" } },
        .{ .end_call = .{ .call = "read" } },
        .{ .release = .{ .name = "ticket" } },
    };

    var plan = try build(std.testing.allocator, &bindings, &operations);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), plan.actions.len);
    try std.testing.expectEqual(ActionKind.borrow, plan.actions[0].kind);
    try std.testing.expectEqual(ActionKind.release, plan.actions[1].kind);
}

test "branch join requires every branch to preserve the same ownership state" {
    const left = [_]StateEntry{.{ .name = "ticket", .state = .owned }};
    const right = [_]StateEntry{.{ .name = "ticket", .state = .owned }};
    const joined = try join_states(std.testing.allocator, &.{ &left, &right });
    defer std.testing.allocator.free(joined);
    try std.testing.expectEqual(@as(usize, 1), joined.len);
    try std.testing.expectEqual(OwnershipState.owned, joined[0].state);

    const moved = [_]StateEntry{.{ .name = "ticket", .state = .moved }};
    try std.testing.expectError(
        error.BranchOwnershipMismatch,
        join_states(std.testing.allocator, &.{ &left, &moved }),
    );
}

test "early drop clears the owned binding" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    const bindings = [_]ResourceBinding{try ResourceBinding.init("ticket", &ticket)};
    const operations = [_]Operation{.{ .early_drop = .{ .name = "ticket" } }};

    var plan = try build(std.testing.allocator, &bindings, &operations);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), plan.actions.len);
    try std.testing.expectEqual(ActionKind.early_drop, plan.actions[0].kind);
    try std.testing.expectEqual(ActionKind.clear, plan.actions[1].kind);
}

test "duplicate release is rejected" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    const bindings = [_]ResourceBinding{try ResourceBinding.init("ticket", &ticket)};
    const operations = [_]Operation{
        .{ .release = .{ .name = "ticket" } },
        .{ .release = .{ .name = "ticket" } },
    };
    try std.testing.expectError(error.DuplicateRelease, build(std.testing.allocator, &bindings, &operations));
}

test "borrowed value cannot escape its direct call region" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    const bindings = [_]ResourceBinding{try ResourceBinding.init("ticket", &ticket)};
    const operations = [_]Operation{.{ .borrow_escape = .{ .owner = "ticket", .call = "read", .destination = "saved" } }};
    try std.testing.expectError(error.BorrowEscapesCall, build(std.testing.allocator, &bindings, &operations));
}

test "list producer ownership transfers every ticket without guest release" {
    var plan = try ListProducerOwnershipPlan.init(std.testing.allocator, 3, 3, &.{ 0, 1, 3 });
    defer plan.deinit();
    try plan.apply(.{ .allocate = {} });
    try plan.apply(.{ .create_ticket = 0 });
    try plan.apply(.{ .create_ticket = 1 });
    try plan.apply(.{ .create_ticket = 2 });
    try plan.apply(.{ .enqueue = {} });
    try plan.apply(.{ .transfer = {} });
    try plan.apply(.{ .clear_source_slot = 0 });
    try plan.apply(.{ .clear_source_slot = 1 });
    try plan.apply(.{ .clear_source_slot = 2 });
    try std.testing.expectError(error.TransferredRelease, plan.apply(.{ .release_ticket = 0 }));
    try plan.apply(.{ .release_list = {} });
    try plan.apply(.{ .terminal_finalize = {} });

    try std.testing.expectEqual(ListProducerState.transferred, plan.ticket_states[0]);
    try std.testing.expectEqual(ListProducerState.finalized, plan.list_state);
    try std.testing.expectEqual(@as(usize, 14), plan.actions.items.len);
    try std.testing.expectEqual(ListProducerActionKind.release_list, plan.actions.items[9].kind);
    try std.testing.expectEqual(ListProducerActionKind.drop_stream, plan.actions.items[10].kind);
    try std.testing.expectEqual(ListProducerActionKind.drop_future, plan.actions.items[11].kind);
    try std.testing.expectEqual(ListProducerActionKind.drop_frame, plan.actions.items[12].kind);
    try std.testing.expectEqual(ListProducerActionKind.terminal_finalize, plan.actions.items[13].kind);
}

test "list producer ownership cancellation before transfer releases queued children first" {
    var plan = try ListProducerOwnershipPlan.init(std.testing.allocator, 3, 3, &.{ 0, 1, 3 });
    defer plan.deinit();
    try plan.apply(.{ .allocate = {} });
    try plan.apply(.{ .create_ticket = 0 });
    try plan.apply(.{ .create_ticket = 1 });
    try plan.apply(.{ .create_ticket = 2 });
    try plan.apply(.{ .enqueue = {} });
    try plan.apply(.{ .cancel = {} });
    try std.testing.expectEqual(ListProducerState.finalized, plan.list_state);
    for (plan.ticket_states) |state| try std.testing.expectEqual(ListProducerState.finalized, state);
    try std.testing.expectEqual(ListProducerActionKind.release_ticket, plan.actions.items[5].kind);
    try std.testing.expectEqual(ListProducerActionKind.release_ticket, plan.actions.items[6].kind);
    try std.testing.expectEqual(ListProducerActionKind.release_ticket, plan.actions.items[7].kind);
    try std.testing.expectEqual(ListProducerActionKind.release_list, plan.actions.items[8].kind);
    try std.testing.expectEqual(ListProducerActionKind.drop_stream, plan.actions.items[9].kind);
    try std.testing.expectEqual(ListProducerActionKind.drop_future, plan.actions.items[10].kind);
    try std.testing.expectEqual(ListProducerActionKind.drop_frame, plan.actions.items[11].kind);
}

test "list producer ownership cancellation after transfer clears slots without ticket drops" {
    var plan = try ListProducerOwnershipPlan.init(std.testing.allocator, 1, 3, &.{ 0, 1, 3 });
    defer plan.deinit();
    try plan.apply(.{ .allocate = {} });
    try plan.apply(.{ .create_ticket = 0 });
    try plan.apply(.{ .enqueue = {} });
    try plan.apply(.{ .transfer = {} });
    try plan.apply(.{ .cancel = {} });
    try std.testing.expectEqual(ListProducerState.transferred, plan.ticket_states[0]);
    try std.testing.expectEqual(ListProducerState.finalized, plan.list_state);
    for (plan.actions.items) |action| try std.testing.expect(action.kind != .release_ticket);
}

test "list producer ownership rejects invalid mode and partial creation cleans only live tickets" {
    try std.testing.expectError(
        error.InvalidProducerCardinality,
        ListProducerOwnershipPlan.init(std.testing.allocator, 2, 3, &.{ 0, 1, 3 }),
    );

    var plan = try ListProducerOwnershipPlan.init(std.testing.allocator, 3, 3, &.{ 0, 1, 3 });
    defer plan.deinit();
    try plan.apply(.{ .allocate = {} });
    try plan.apply(.{ .create_ticket = 0 });
    try plan.apply(.{ .create_ticket = 1 });
    try plan.apply(.{ .cancel = {} });
    try std.testing.expectEqual(ListProducerState.unallocated, plan.ticket_states[2]);
    try std.testing.expectEqual(ListProducerActionKind.release_ticket, plan.actions.items[3].kind);
    try std.testing.expectEqual(@as(u32, 0), plan.actions.items[3].index.?);
    try std.testing.expectEqual(ListProducerActionKind.release_ticket, plan.actions.items[4].kind);
    try std.testing.expectEqual(@as(u32, 1), plan.actions.items[4].index.?);
}

test "dynamic list producer ownership transfers every admitted runtime length" {
    for (0..4) |raw_length| {
        const length: u32 = @intCast(raw_length);
        var plan = try ListProducerOwnershipPlan.init(std.testing.allocator, length, 3, &.{ 0, 1, 2, 3 });
        defer plan.deinit();
        try plan.apply(.{ .allocate = {} });
        for (0..raw_length) |raw_index| try plan.apply(.{ .create_ticket = @intCast(raw_index) });
        try plan.apply(.{ .enqueue = {} });
        try plan.apply(.{ .transfer = {} });
        for (0..raw_length) |raw_index| try plan.apply(.{ .clear_source_slot = @intCast(raw_index) });
        try plan.apply(.{ .release_list = {} });
        try plan.apply(.{ .terminal_finalize = {} });
        try std.testing.expectEqual(ListProducerState.finalized, plan.list_state);
        for (plan.ticket_states) |state| try std.testing.expectEqual(ListProducerState.transferred, state);
        for (plan.actions.items) |action| try std.testing.expect(action.kind != .release_ticket);
    }
}

test "dynamic list producer ownership cancels partial creation without guest leaks" {
    for (0..4) |raw_length| {
        const length: u32 = @intCast(raw_length);
        var plan = try ListProducerOwnershipPlan.init(std.testing.allocator, length, 3, &.{ 0, 1, 2, 3 });
        defer plan.deinit();
        try plan.apply(.{ .allocate = {} });
        const created = raw_length / 2;
        for (0..created) |raw_index| try plan.apply(.{ .create_ticket = @intCast(raw_index) });
        try plan.apply(.{ .cancel = {} });
        try std.testing.expectEqual(ListProducerState.finalized, plan.list_state);
        for (plan.ticket_states, 0..) |state, raw_index| {
            const expected = if (raw_index < created) ListProducerState.finalized else ListProducerState.unallocated;
            try std.testing.expectEqual(expected, state);
        }
        var releases: usize = 0;
        for (plan.actions.items) |action| {
            if (action.kind == .release_ticket) releases += 1;
        }
        try std.testing.expectEqual(created, releases);
    }
}

test "list producer ownership rejects duplicate release and source clear" {
    var plan = try ListProducerOwnershipPlan.init(std.testing.allocator, 1, 3, &.{ 0, 1, 3 });
    defer plan.deinit();
    try plan.apply(.{ .allocate = {} });
    try plan.apply(.{ .create_ticket = 0 });
    try plan.apply(.{ .release_ticket = 0 });
    try std.testing.expectError(error.DuplicateRelease, plan.apply(.{ .release_ticket = 0 }));
    try plan.apply(.{ .release_list = {} });
    try std.testing.expectError(error.DuplicateRelease, plan.apply(.{ .release_list = {} }));

    var transferred = try ListProducerOwnershipPlan.init(std.testing.allocator, 1, 3, &.{ 0, 1, 3 });
    defer transferred.deinit();
    try transferred.apply(.{ .allocate = {} });
    try transferred.apply(.{ .create_ticket = 0 });
    try transferred.apply(.{ .enqueue = {} });
    try transferred.apply(.{ .transfer = {} });
    try transferred.apply(.{ .clear_source_slot = 0 });
    try std.testing.expectError(error.SlotAlreadyCleared, transferred.apply(.{ .clear_source_slot = 0 }));
}

test "list producer ownership branch join rejects maybe owner" {
    const left = [_]ListProducerStateEntry{.{ .name = "ticket[0]", .state = .guest_owned }};
    const maybe = [_]ListProducerStateEntry{.{ .name = "ticket[0]", .state = .maybe }};
    try std.testing.expectError(
        error.BranchOwnershipMismatch,
        join_list_producer_states(std.testing.allocator, &.{ &left, &maybe }),
    );
}
