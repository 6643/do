//! Pure GC root/liveness facts.
const std = @import("std");
const representation = @import("codegen_gc_representation.zig");

pub const RootMode = enum { synchronous, suspendable };
pub const RootPoint = enum { local_bind, overwrite, branch_join, loop_join, return_value, suspend_frame, resume_frame, cancel_frame, terminal };
pub const RootLocal = struct { name: []const u8, rep: representation.ValueRep };
pub const RootSlot = struct { name: []const u8, point: RootPoint };
pub const RootPlan = struct { slots: []const RootSlot };
pub const SuspendableRootField = struct {
    name: []const u8,
    field_index: u32,
    live_until: RootPoint,
};
pub const SuspendableRootPlan = struct { fields: []const SuspendableRootField };

pub fn build_root_plan(allocator: std.mem.Allocator, locals: []const RootLocal, mode: RootMode) !RootPlan {
    var slot_count: usize = 0;
    for (locals, 0..) |local, index| {
        if (local.rep == .resource_handle) return error.ResourceCannotBeGcRoot;
        if (local.rep != .gc_managed) continue;
        for (locals[0..index]) |previous| {
            if (previous.rep == .gc_managed and std.mem.eql(u8, previous.name, local.name)) {
                return error.DuplicateRootLocal;
            }
        }
        slot_count += if (mode == .synchronous) 1 else 5;
    }

    var slots = try allocator.alloc(RootSlot, slot_count);
    errdefer allocator.free(slots);
    var cursor: usize = 0;
    for (locals) |local| {
        if (local.rep != .gc_managed) continue;
        slots[cursor] = .{ .name = local.name, .point = .local_bind };
        cursor += 1;
        if (mode != .suspendable) continue;
        slots[cursor] = .{ .name = local.name, .point = .suspend_frame };
        slots[cursor + 1] = .{ .name = local.name, .point = .resume_frame };
        slots[cursor + 2] = .{ .name = local.name, .point = .cancel_frame };
        slots[cursor + 3] = .{ .name = local.name, .point = .terminal };
        cursor += 4;
    }
    return .{ .slots = slots };
}

pub fn deinit_root_plan(allocator: std.mem.Allocator, plan: RootPlan) void {
    allocator.free(plan.slots);
}

/// Build the frame-owned portion of a suspendable root plan. Resource handles
/// are intentionally excluded: their lifetime is governed by the Component
/// resource plan, not by GC reachability.
pub fn build_suspendable_root_plan(
    allocator: std.mem.Allocator,
    locals: []const RootLocal,
) !SuspendableRootPlan {
    var field_count: usize = 0;
    for (locals, 0..) |local, index| {
        if (local.rep == .resource_handle) return error.ResourceCannotBeGcRoot;
        if (local.rep != .gc_managed) continue;
        for (locals[0..index]) |previous| {
            if (previous.rep == .gc_managed and std.mem.eql(u8, previous.name, local.name)) {
                return error.DuplicateRootLocal;
            }
        }
        field_count += 1;
    }

    const fields = try allocator.alloc(SuspendableRootField, field_count);
    errdefer allocator.free(fields);
    var cursor: usize = 0;
    for (locals) |local| {
        if (local.rep != .gc_managed) continue;
        fields[cursor] = .{
            .name = local.name,
            .field_index = @intCast(cursor),
            .live_until = .terminal,
        };
        cursor += 1;
    }
    return .{ .fields = fields };
}

pub fn deinit_suspendable_root_plan(allocator: std.mem.Allocator, plan: SuspendableRootPlan) void {
    allocator.free(plan.fields);
}
