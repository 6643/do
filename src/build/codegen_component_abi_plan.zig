//! Pure canonical lift/lower facts. GC references never cross this boundary.
const std = @import("std");

pub const SlotDirection = enum { lift, lower };
pub const CanonicalSlot = struct {
    source_type: []const u8,
    canonical_type: []const u8,
    direction: SlotDirection,
    contains_gc_reference: bool = false,
};

pub const AbiMemberShape = struct {
    package: []const u8,
    world: []const u8,
    member: []const u8,
    arguments: []const CanonicalSlot,
    results: []const CanonicalSlot,
};

pub const AbiPlan = struct {
    package: []const u8,
    world: []const u8,
    member: []const u8,
    arguments: []const CanonicalSlot,
    results: []const CanonicalSlot,
};

pub fn build_abi_plan(allocator: std.mem.Allocator, shape: AbiMemberShape) !AbiPlan {
    if (shape.package.len == 0 or shape.world.len == 0 or shape.member.len == 0) return error.InvalidAbiIdentity;
    try validate_slots(shape.arguments);
    try validate_slots(shape.results);

    const package = try allocator.dupe(u8, shape.package);
    errdefer allocator.free(package);
    const world = try allocator.dupe(u8, shape.world);
    errdefer allocator.free(world);
    const member = try allocator.dupe(u8, shape.member);
    errdefer allocator.free(member);
    const arguments = try allocator.dupe(CanonicalSlot, shape.arguments);
    errdefer allocator.free(arguments);
    const results = try allocator.dupe(CanonicalSlot, shape.results);
    errdefer allocator.free(results);
    return .{ .package = package, .world = world, .member = member, .arguments = arguments, .results = results };
}

pub fn validate_abi_plan(plan: AbiPlan) !void {
    try validate_slots(plan.arguments);
    try validate_slots(plan.results);
}

pub fn deinit_abi_plan(allocator: std.mem.Allocator, plan: AbiPlan) void {
    allocator.free(plan.package);
    allocator.free(plan.world);
    allocator.free(plan.member);
    allocator.free(plan.arguments);
    allocator.free(plan.results);
}

fn validate_slots(slots: []const CanonicalSlot) !void {
    for (slots) |slot| {
        if (slot.contains_gc_reference) return error.GcReferenceCannotCrossCanonicalAbi;
    }
}
