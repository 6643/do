//! Pure GC root/liveness facts.
const std = @import("std");
const representation = @import("codegen_gc_representation.zig");

pub const RootMode = enum { synchronous, suspendable };
pub const RootPoint = enum { local_bind, overwrite, branch_join, loop_join, return_value, suspend_frame, resume_frame, cancel_frame, terminal };
pub const RootLocal = struct { name: []const u8, rep: representation.ValueRep };
pub const RootSlot = struct { name: []const u8, point: RootPoint };
pub const RootPlan = struct { slots: []const RootSlot };

pub fn build_root_plan(allocator: std.mem.Allocator, locals: []const RootLocal, mode: RootMode) !RootPlan {
    var slot_count: usize = 0;
    for (locals) |local| {
        if (local.rep == .resource_handle) return error.ResourceCannotBeGcRoot;
        if (local.rep == .gc_managed) slot_count += if (mode == .synchronous) 1 else 5;
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
