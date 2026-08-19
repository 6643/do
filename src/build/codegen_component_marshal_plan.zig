//! Synchronous, value-only canonical lift/lower plans.
//!
//! This module deliberately stops at the typed plan boundary. It does not
//! emit WAT, allocate linear memory, or admit resources and async shapes.
const std = @import("std");
const wit_types = @import("wit_abi_types.zig");
const wit_layout = @import("wit_abi_layout.zig");
const component_abi = @import("codegen_component_abi_plan.zig");

pub const DescriptorIdentity = struct {
    package: []const u8,
    world: []const u8,
    member: []const u8,
    revision: []const u8,
    schema_hash: []const u8,
};

pub const DescriptorRegistryEntry = DescriptorIdentity;

pub const Direction = enum { lift, lower };

pub const NodeKind = enum {
    scalar,
    text,
    list,
    record,
};

pub const CanonicalShape = enum {
    scalar,
    ptr_len,
    aggregate,
};

pub const MarshalNode = struct {
    kind: NodeKind,
    canonical_shape: CanonicalShape,
    scalar_kind: ?wit_types.ScalarKind = null,
    provisional_offset: u32,
    provisional_size: u32,
    provisional_alignment: u32,
    measured: ?MeasuredFacts = null,
    children: []MarshalNode,
    contains_gc_reference: bool = false,
};

pub const MeasuredFacts = struct {
    offset: u32,
    byte_size: u32,
    alignment: u32,
    element_stride: ?u32 = null,
    core_type: ?wit_layout.CoreWord = null,
    pointer_offset: ?u32 = null,
    length_offset: ?u32 = null,
    indirect: ?wit_layout.IndirectMeasurement = null,
};

pub const MeasuredNode = struct {
    layout: MeasuredLayout,
    children: []const MeasuredNode = &.{},
};

pub const MeasuredLayout = union(enum) {
    scalar: wit_layout.ScalarMeasurement,
    text: wit_layout.TextLayoutMeasurement,
    list: wit_layout.ListLayoutMeasurement,
    byte_list: wit_layout.ByteListLayoutMeasurement,
    record: wit_layout.RecordMeasurement,
};

pub const SyncValuePlan = struct {
    descriptor: DescriptorIdentity,
    direction: Direction,
    root: MarshalNode,
    abi: component_abi.AbiPlan,
    contains_gc_reference: bool,
};

pub fn build_sync_value_plan(
    allocator: std.mem.Allocator,
    descriptor: DescriptorIdentity,
    source: *const wit_types.AbiType,
    direction: Direction,
) !SyncValuePlan {
    try validate_descriptor(descriptor);

    const root = try build_node(allocator, source, 0);
    errdefer deinit_node(allocator, root);

    const slot = component_abi.CanonicalSlot{
        .source_type = source_type_name(source),
        .canonical_type = try canonical_type_name(source),
        .direction = switch (direction) {
            .lift => .lift,
            .lower => .lower,
        },
        .contains_gc_reference = false,
    };
    const abi_plan = try component_abi.build_abi_plan(allocator, .{
        .package = descriptor.package,
        .world = descriptor.world,
        .member = descriptor.member,
        .arguments = if (direction == .lower) &.{slot} else &.{},
        .results = if (direction == .lift) &.{slot} else &.{},
    });
    errdefer component_abi.deinit_abi_plan(allocator, abi_plan);
    try component_abi.validate_abi_plan(abi_plan);

    const package = try allocator.dupe(u8, descriptor.package);
    errdefer allocator.free(package);
    const world = try allocator.dupe(u8, descriptor.world);
    errdefer allocator.free(world);
    const member = try allocator.dupe(u8, descriptor.member);
    errdefer allocator.free(member);
    const revision = try allocator.dupe(u8, descriptor.revision);
    errdefer allocator.free(revision);
    const schema_hash = try allocator.dupe(u8, descriptor.schema_hash);
    errdefer allocator.free(schema_hash);

    return .{
        .descriptor = .{
            .package = package,
            .world = world,
            .member = member,
            .revision = revision,
            .schema_hash = schema_hash,
        },
        .direction = direction,
        .root = root,
        .abi = abi_plan,
        .contains_gc_reference = false,
    };
}

pub fn validate_descriptor_binding(
    descriptor: DescriptorIdentity,
    registry: DescriptorRegistryEntry,
) !void {
    try validate_descriptor(descriptor);
    try validate_descriptor(registry);
    if (!valid_sha256_hash(descriptor.schema_hash) or !valid_sha256_hash(registry.schema_hash)) {
        return error.InvalidDescriptorIdentity;
    }
    if (!std.mem.eql(u8, descriptor.package, registry.package) or
        !std.mem.eql(u8, descriptor.world, registry.world) or
        !std.mem.eql(u8, descriptor.member, registry.member) or
        !std.mem.eql(u8, descriptor.revision, registry.revision) or
        !std.mem.eql(u8, descriptor.schema_hash, registry.schema_hash))
    {
        return error.DescriptorDrift;
    }
}

pub fn build_sync_value_plan_with_registry(
    allocator: std.mem.Allocator,
    descriptor: DescriptorIdentity,
    registry: DescriptorRegistryEntry,
    source: *const wit_types.AbiType,
    direction: Direction,
) !SyncValuePlan {
    try validate_descriptor_binding(descriptor, registry);
    return build_sync_value_plan(allocator, descriptor, source, direction);
}

pub fn build_sync_value_plan_with_layout(
    allocator: std.mem.Allocator,
    descriptor: DescriptorIdentity,
    source: *const wit_types.AbiType,
    direction: Direction,
    measured: MeasuredNode,
) !SyncValuePlan {
    try validate_descriptor(descriptor);

    var root = try build_node(allocator, source, 0);
    errdefer deinit_node(allocator, root);
    try bind_measured_node(allocator, &root, source, measured, null);

    const slot = component_abi.CanonicalSlot{
        .source_type = source_type_name(source),
        .canonical_type = try canonical_type_name(source),
        .direction = switch (direction) {
            .lift => .lift,
            .lower => .lower,
        },
        .contains_gc_reference = false,
    };
    const abi_plan = try component_abi.build_abi_plan(allocator, .{
        .package = descriptor.package,
        .world = descriptor.world,
        .member = descriptor.member,
        .arguments = if (direction == .lower) &.{slot} else &.{},
        .results = if (direction == .lift) &.{slot} else &.{},
    });
    errdefer component_abi.deinit_abi_plan(allocator, abi_plan);
    try component_abi.validate_abi_plan(abi_plan);

    const package = try allocator.dupe(u8, descriptor.package);
    errdefer allocator.free(package);
    const world = try allocator.dupe(u8, descriptor.world);
    errdefer allocator.free(world);
    const member = try allocator.dupe(u8, descriptor.member);
    errdefer allocator.free(member);
    const revision = try allocator.dupe(u8, descriptor.revision);
    errdefer allocator.free(revision);
    const schema_hash = try allocator.dupe(u8, descriptor.schema_hash);
    errdefer allocator.free(schema_hash);

    return .{
        .descriptor = .{
            .package = package,
            .world = world,
            .member = member,
            .revision = revision,
            .schema_hash = schema_hash,
        },
        .direction = direction,
        .root = root,
        .abi = abi_plan,
        .contains_gc_reference = false,
    };
}

pub fn deinit_sync_value_plan(allocator: std.mem.Allocator, plan: SyncValuePlan) void {
    deinit_node(allocator, plan.root);
    component_abi.deinit_abi_plan(allocator, plan.abi);
    allocator.free(plan.descriptor.package);
    allocator.free(plan.descriptor.world);
    allocator.free(plan.descriptor.member);
    allocator.free(plan.descriptor.revision);
    allocator.free(plan.descriptor.schema_hash);
}

pub fn validate_sync_value_plan(plan: *const SyncValuePlan) !void {
    if (plan.contains_gc_reference or node_contains_gc_reference(&plan.root)) {
        return error.GcReferenceCannotCrossCanonicalAbi;
    }
    try component_abi.validate_abi_plan(plan.abi);
}

fn node_contains_gc_reference(node: *const MarshalNode) bool {
    if (node.contains_gc_reference) return true;
    for (node.children) |*child| {
        if (node_contains_gc_reference(child)) return true;
    }
    return false;
}

fn validate_descriptor(descriptor: DescriptorIdentity) !void {
    if (descriptor.package.len == 0 or descriptor.world.len == 0 or
        descriptor.member.len == 0 or descriptor.revision.len == 0 or
        descriptor.schema_hash.len == 0)
    {
        return error.InvalidDescriptorIdentity;
    }
}

fn valid_sha256_hash(value: []const u8) bool {
    if (value.len != "sha256:".len + 64 or !std.mem.startsWith(u8, value, "sha256:")) return false;
    for (value["sha256:".len..]) |ch| {
        if (!std.ascii.isHex(ch)) return false;
    }
    return true;
}

fn source_type_name(source: *const wit_types.AbiType) []const u8 {
    return switch (source.kind()) {
        .scalar => "scalar",
        .text => "text",
        .list => "list",
        .record => "record",
        else => "unsupported",
    };
}

fn canonical_type_name(source: *const wit_types.AbiType) ![]const u8 {
    return switch (source.kind()) {
        .scalar => switch (source.scalar_kind() orelse return error.UnsupportedMarshalShape) {
            .u64, .i64 => "i64",
            .f32 => "f32",
            .f64 => "f64",
            else => "i32",
        },
        .text, .list => "(i32,i32)",
        .record => "memory",
        .resource => error.ResourceBoundaryUnsupported,
        .unit, .tuple, .option, .result, .variant => error.UnsupportedMarshalShape,
    };
}

fn build_node(allocator: std.mem.Allocator, source: *const wit_types.AbiType, offset: u32) !MarshalNode {
    return switch (source.kind()) {
        .scalar => scalar_node(source, offset),
        .text => .{
            .kind = .text,
            .canonical_shape = .ptr_len,
            .provisional_offset = offset,
            .provisional_size = 8,
            .provisional_alignment = 4,
            .children = &.{},
        },
        .list => {
            const element = source.list_element() orelse return error.UnsupportedMarshalShape;
            switch (element.kind()) {
                .scalar, .text => {},
                else => return error.UnsupportedMarshalShape,
            }
            var children = try allocator.alloc(MarshalNode, 1);
            errdefer allocator.free(children);
            children[0] = try build_node(allocator, element, 0);
            return .{
                .kind = .list,
                .canonical_shape = .ptr_len,
                .provisional_offset = offset,
                .provisional_size = 8,
                .provisional_alignment = 4,
                .children = children,
            };
        },
        .record => {
            const field_count = source.record_field_count() orelse return error.UnsupportedMarshalShape;
            var children = try allocator.alloc(MarshalNode, field_count);
            var initialized: usize = 0;
            errdefer {
                for (children[0..initialized]) |child| deinit_node(allocator, child);
                allocator.free(children);
            }

            var field_offset: u32 = 0;
            var record_alignment: u32 = 1;
            while (initialized < field_count) : (initialized += 1) {
                const field = source.record_field_at(initialized) orelse return error.UnsupportedMarshalShape;
                const field_alignment = try canonical_alignment(field.value);
                record_alignment = @max(record_alignment, field_alignment);
                const aligned_offset = align_up(field_offset, field_alignment);
                children[initialized] = try build_node(allocator, field.value, aligned_offset);
                field_offset = aligned_offset + children[initialized].provisional_size;
            }
            return .{
                .kind = .record,
                .canonical_shape = .aggregate,
                .provisional_offset = offset,
                .provisional_size = align_up(field_offset, record_alignment),
                .provisional_alignment = record_alignment,
                .children = children,
            };
        },
        .resource => error.ResourceBoundaryUnsupported,
        .unit, .tuple, .option, .result, .variant => error.UnsupportedMarshalShape,
    };
}

fn bind_measured_node(
    allocator: std.mem.Allocator,
    node: *MarshalNode,
    source: *const wit_types.AbiType,
    measured: MeasuredNode,
    placement_offset: ?u32,
) !void {
    switch (measured.layout) {
        .scalar => |facts| {
            var layout = try wit_layout.LayoutPlan.scalar(allocator, source, facts);
            defer layout.deinit();
            if (measured.children.len != 0) return error.MeasuredChildCountMismatch;
            node.measured = .{
                .offset = placement_offset orelse facts.offset,
                .byte_size = facts.byte_size,
                .alignment = facts.alignment,
                .core_type = facts.core_type,
            };
        },
        .text => |facts| {
            var layout = try wit_layout.TextLayoutPlan.init(allocator, source, facts);
            defer layout.deinit();
            if (measured.children.len != 0) return error.MeasuredChildCountMismatch;
            node.measured = .{
                .offset = placement_offset orelse 0,
                .byte_size = facts.byte_size,
                .alignment = facts.alignment,
                .pointer_offset = facts.pointer_offset,
                .length_offset = facts.length_offset,
            };
        },
        .list => |facts| {
            if (source.kind() != .list) return error.MeasuredKindMismatch;
            var layout = try wit_layout.ListLayoutPlan.init(allocator, source, facts);
            defer layout.deinit();
            if (measured.children.len != 1) return error.MeasuredChildCountMismatch;
            const element = source.list_element() orelse return error.UnsupportedMeasuredShape;
            try bind_measured_node(allocator, &node.children[0], element, measured.children[0], facts.ticket_offset);
            node.measured = .{
                .offset = placement_offset orelse 0,
                .byte_size = 8,
                .alignment = 4,
                .element_stride = facts.element_stride,
                .pointer_offset = facts.pointer_offset,
                .length_offset = facts.length_offset,
            };
        },
        .byte_list => |facts| {
            var layout = try wit_layout.ByteListLayoutPlan.init(allocator, source, facts);
            defer layout.deinit();
            if (measured.children.len != 0) return error.MeasuredChildCountMismatch;
            if (node.children.len != 1) return error.MeasuredChildCountMismatch;
            node.children[0].measured = .{
                .offset = 0,
                .byte_size = facts.element_byte_size,
                .alignment = facts.element_alignment,
            };
            node.measured = .{
                .offset = placement_offset orelse 0,
                .byte_size = 8,
                .alignment = 4,
                .element_stride = facts.element_stride,
                .pointer_offset = facts.pointer_offset,
                .length_offset = facts.length_offset,
            };
        },
        .record => |facts| {
            if (source.kind() != .record) return error.MeasuredKindMismatch;
            var layout = try wit_layout.LayoutPlan.record(allocator, source, facts);
            defer layout.deinit();
            for (facts.fields) |field| {
                if (field.indirect != null) return error.UnsupportedMeasuredShape;
            }
            const field_count = source.record_field_count() orelse return error.UnsupportedMeasuredShape;
            if (facts.fields.len != field_count or measured.children.len != field_count) {
                return error.MeasuredChildCountMismatch;
            }
            for (facts.fields, 0..) |field, index| {
                const source_field = source.record_field_at(index) orelse return error.UnsupportedMeasuredShape;
                if (!std.mem.eql(u8, source_field.name, field.name)) return error.MeasuredFieldMismatch;
                try bind_measured_node(allocator, &node.children[index], source_field.value, measured.children[index], field.offset);
                const child_facts = node.children[index].measured orelse return error.MeasuredChildMissing;
                if (child_facts.byte_size != field.byte_size or child_facts.alignment != field.alignment) {
                    return error.MeasuredFieldMismatch;
                }
            }
            node.measured = .{
                .offset = placement_offset orelse 0,
                .byte_size = facts.byte_size,
                .alignment = facts.alignment,
                .indirect = facts.indirect,
            };
        },
    }
}

fn scalar_node(source: *const wit_types.AbiType, offset: u32) !MarshalNode {
    const scalar = source.scalar_kind() orelse return error.UnsupportedMarshalShape;
    const wide = switch (scalar) {
        .u64, .i64, .f64 => true,
        else => false,
    };
    return .{
        .kind = .scalar,
        .canonical_shape = .scalar,
        .scalar_kind = scalar,
        .provisional_offset = offset,
        .provisional_size = if (wide) 8 else 4,
        .provisional_alignment = if (wide) 8 else 4,
        .children = &.{},
    };
}

fn canonical_alignment(source: *const wit_types.AbiType) !u32 {
    return switch (source.kind()) {
        .scalar => (try scalar_node(source, 0)).provisional_alignment,
        .text, .list => 4,
        .record => {
            const field_count = source.record_field_count() orelse return error.UnsupportedMarshalShape;
            var alignment: u32 = 1;
            var index: usize = 0;
            while (index < field_count) : (index += 1) {
                const field = source.record_field_at(index) orelse return error.UnsupportedMarshalShape;
                alignment = @max(alignment, try canonical_alignment(field.value));
            }
            return alignment;
        },
        .resource => error.ResourceBoundaryUnsupported,
        .unit, .tuple, .option, .result, .variant => error.UnsupportedMarshalShape,
    };
}

fn align_up(value: u32, alignment: u32) u32 {
    if (alignment <= 1) return value;
    const remainder = value % alignment;
    return if (remainder == 0) value else value + (alignment - remainder);
}

fn deinit_node(allocator: std.mem.Allocator, node: MarshalNode) void {
    for (node.children) |child| deinit_node(allocator, child);
    if (node.children.len != 0) allocator.free(node.children);
}
