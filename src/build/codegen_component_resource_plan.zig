//! Pure WIT resource transfer and terminal-cleanup facts.
const std = @import("std");

pub const TransferDirection = enum { own_in, own_out, borrow_in };
pub const ResourceTransfer = struct {
    type_name: []const u8,
    direction: TransferDirection,
    drop_authority: bool,
};
pub const TerminalAction = enum { no_resource, drop_owned, retain_for_host };
pub const ResourceFacts = struct {
    transfers: []const ResourceTransfer,
    terminal_actions: []const TerminalAction,
};
pub const TerminalState = enum { pending, completed, cancelled, early_dropped };
pub const TerminalEvent = enum { completed, cancelled, early_drop };
pub const ResourcePlan = struct {
    transfers: []const ResourceTransfer,
    terminal_action: TerminalAction,
    terminal_state: TerminalState,
};

pub fn build_resource_plan(allocator: std.mem.Allocator, facts: ResourceFacts) !ResourcePlan {
    if (facts.terminal_actions.len == 0) return error.MissingTerminalCleanup;
    if (facts.terminal_actions.len != 1) return error.DuplicateTerminalCleanup;
    if (facts.terminal_actions[0] == .no_resource and facts.transfers.len != 0) return error.ResourceCleanupActionMismatch;

    for (facts.transfers, 0..) |transfer, index| {
        if (transfer.type_name.len == 0) return error.InvalidResourceTransfer;
        if (transfer.direction == .borrow_in and transfer.drop_authority) {
            return error.BorrowCannotHaveDropAuthority;
        }
        if (!transfer.drop_authority) continue;
        for (facts.transfers[0..index]) |previous| {
            if (previous.drop_authority and std.mem.eql(u8, previous.type_name, transfer.type_name)) {
                return error.DuplicateResourceDropAuthority;
            }
        }
    }

    const has_drop_authority = for (facts.transfers) |transfer| {
        if (transfer.drop_authority) break true;
    } else false;
    if (facts.terminal_actions[0] == .drop_owned and !has_drop_authority) {
        return error.ResourceCleanupActionMismatch;
    }
    if (facts.terminal_actions[0] == .retain_for_host and has_drop_authority) {
        return error.ResourceCleanupActionMismatch;
    }

    const transfers = try allocator.dupe(ResourceTransfer, facts.transfers);
    return .{
        .transfers = transfers,
        .terminal_action = facts.terminal_actions[0],
        .terminal_state = .pending,
    };
}

pub fn deinit_resource_plan(allocator: std.mem.Allocator, plan: ResourcePlan) void {
    allocator.free(plan.transfers);
}

pub fn claim_terminal(plan: *ResourcePlan, event: TerminalEvent) !void {
    if (plan.terminal_state != .pending) return error.TerminalAlreadyDecided;
    plan.terminal_state = switch (event) {
        .completed => .completed,
        .cancelled => .cancelled,
        .early_drop => .early_dropped,
    };
}
