//! Pure GC root/liveness facts.
const std = @import("std");
const representation = @import("codegen_gc_representation.zig");

pub const RootMode = enum { synchronous, suspendable };
pub const RootPoint = enum { local_bind, overwrite, branch_join, loop_join, return_value, suspend_frame, resume_frame, cancel_frame, terminal };
pub const RootLocal = struct {
    name: []const u8,
    rep: representation.ValueRep,
    bind_at_entry: bool = true,
};
pub const RootSlot = struct {
    name: []const u8,
    point: RootPoint,
    bind_at_entry: bool = true,
};
pub const RootPlan = struct { slots: []const RootSlot };
pub const SuspendableRootField = struct {
    name: []const u8,
    field_index: u32,
    live_until: RootPoint,
};
pub const SuspendableRootPlan = struct { fields: []const SuspendableRootField };

const synchronous_root_points = [_]RootPoint{.local_bind};
const suspendable_root_points = [_]RootPoint{
    .local_bind,
    .overwrite,
    .branch_join,
    .loop_join,
    .return_value,
    .suspend_frame,
    .resume_frame,
    .cancel_frame,
    .terminal,
};

pub fn build_root_plan(allocator: std.mem.Allocator, locals: []const RootLocal, mode: RootMode) !RootPlan {
    const points = if (mode == .synchronous)
        synchronous_root_points[0..]
    else
        suspendable_root_points[0..];
    var slot_count: usize = 0;
    for (locals, 0..) |local, index| {
        if (local.rep == .resource_handle) return error.ResourceCannotBeGcRoot;
        if (local.rep != .gc_managed) continue;
        for (locals[0..index]) |previous| {
            if (previous.rep == .gc_managed and std.mem.eql(u8, previous.name, local.name)) {
                return error.DuplicateRootLocal;
            }
        }
        slot_count += points.len;
    }

    var slots = try allocator.alloc(RootSlot, slot_count);
    errdefer allocator.free(slots);
    var cursor: usize = 0;
    for (locals) |local| {
        if (local.rep != .gc_managed) continue;
        for (points) |point| {
            slots[cursor] = .{ .name = local.name, .point = point, .bind_at_entry = local.bind_at_entry };
            cursor += 1;
        }
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
