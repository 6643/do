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
pub const ResourcePlan = struct {
    transfers: []const ResourceTransfer,
    terminal_action: TerminalAction,
};

pub fn build_resource_plan(allocator: std.mem.Allocator, facts: ResourceFacts) !ResourcePlan {
    if (facts.terminal_actions.len == 0) return error.MissingTerminalCleanup;
    if (facts.terminal_actions.len != 1) return error.DuplicateTerminalCleanup;
    if (facts.terminal_actions[0] == .no_resource and facts.transfers.len != 0) return error.ResourceCleanupActionMismatch;

    const transfers = try allocator.dupe(ResourceTransfer, facts.transfers);
    return .{ .transfers = transfers, .terminal_action = facts.terminal_actions[0] };
}

pub fn deinit_resource_plan(allocator: std.mem.Allocator, plan: ResourcePlan) void {
    allocator.free(plan.transfers);
}
