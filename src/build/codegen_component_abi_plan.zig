//! Pure canonical lift/lower facts. GC references never cross this boundary.
const std = @import("std");

pub const SlotDirection = enum { lift, lower };
pub const CanonicalWord = enum { i32, i64, f32, f64 };

pub const CanonicalSpan = struct {
    offset: u32,
    byte_size: u32,
    alignment: u32,
};

pub const CanonicalPayload = struct {
    offset: u32,
    byte_size: u32,
    alignment: u32,
    core_words: []CanonicalWord,
};

pub const CanonicalCase = struct {
    tag: u32,
    payload: ?CanonicalPayload,
};

pub const CanonicalSignature = struct {
    direction: SlotDirection,
    parameters: []CanonicalWord,
    results: []CanonicalWord,
    indirect: bool,
    result_area: ?CanonicalSpan,
    discriminant: ?CanonicalSpan,
    cases: []CanonicalCase,

    pub fn deinit(self: *CanonicalSignature, allocator: std.mem.Allocator) void {
        allocator.free(self.parameters);
        allocator.free(self.results);
        for (self.cases) |*case| {
            if (case.payload) |*payload| allocator.free(payload.core_words);
        }
        allocator.free(self.cases);
        self.parameters = &.{};
        self.results = &.{};
        self.cases = &.{};
    }
};

pub fn validate_canonical_signature(signature: CanonicalSignature) !void {
    if (signature.indirect and (signature.parameters.len != 1 or signature.parameters[0] != .i32)) {
        return error.InvalidCanonicalSignature;
    }
    for (signature.parameters) |word| validate_canonical_word(word);
    for (signature.results) |word| validate_canonical_word(word);
    for (signature.cases) |case| {
        if (case.payload) |payload| {
            for (payload.core_words) |word| validate_canonical_word(word);
        }
    }
}

fn validate_canonical_word(word: CanonicalWord) void {
    switch (word) {
        .i32, .i64, .f32, .f64 => {},
    }
}

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
        if (slot.contains_gc_reference or canonical_type_contains_gc_reference(slot.canonical_type)) {
            return error.GcReferenceCannotCrossCanonicalAbi;
        }
    }
}

fn canonical_type_contains_gc_reference(canonical_type: []const u8) bool {
    const trimmed = std.mem.trim(u8, canonical_type, " \t\r\n");
    return std.mem.indexOf(u8, trimmed, "(ref") != null or
        std.mem.startsWith(u8, trimmed, "ref ");
}
