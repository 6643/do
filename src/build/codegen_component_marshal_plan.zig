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
    map,
    record,
    option,
    result,
    variant,
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
    record_type_name: ?[]u8 = null,
    provisional_offset: u32,
    provisional_size: u32,
    provisional_alignment: u32,
    measured: ?MeasuredFacts = null,
    children: []MarshalNode,
    contains_gc_reference: bool = false,
    variant_tag_offset: ?u32 = null,
    variant_cases: []VariantCase = &.{},
};

pub const VariantCase = struct {
    name: []u8,
    tag: u32,
    payload_child: ?usize,
    payload_offset: ?u32 = null,
    payload_byte_size: ?u32 = null,
    payload_alignment: ?u32 = null,
    payload_core_type: ?wit_layout.CoreWord = null,
};

pub const MeasuredFacts = struct {
    offset: u32,
    byte_size: u32,
    alignment: u32,
    element_stride: ?u32 = null,
    element_byte_size: ?u32 = null,
    element_alignment: ?u32 = null,
    capacity: ?u32 = null,
    core_type: ?wit_layout.CoreWord = null,
    pointer_offset: ?u32 = null,
    length_offset: ?u32 = null,
    map_key_offset: ?u32 = null,
    map_value_offset: ?u32 = null,
    map_pair_byte_size: ?u32 = null,
    map_pair_alignment: ?u32 = null,
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
    map: wit_layout.MapLayoutMeasurement,
    record: wit_layout.RecordMeasurement,
    variant: wit_layout.VariantMeasurement,
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
        .map => "map",
        .record => "record",
        .option => "option",
        .result => "result",
        .variant => "variant",
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
        .text, .list, .map => "(i32,i32)",
        .record => "memory",
        .option, .result, .variant => "memory",
        .resource => error.ResourceBoundaryUnsupported,
        .unit, .tuple => error.UnsupportedMarshalShape,
    };
}

fn build_node(allocator: std.mem.Allocator, source: *const wit_types.AbiType, offset: u32) anyerror!MarshalNode {
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
        .map => {
            const key = source.map_key() orelse return error.UnsupportedMarshalShape;
            const value = source.map_value() orelse return error.UnsupportedMarshalShape;
            if (key.kind() != .scalar and key.kind() != .text) return error.UnsupportedMarshalShape;

            var children = try allocator.alloc(MarshalNode, 2);
            var initialized: usize = 0;
            errdefer {
                for (children[0..initialized]) |child| deinit_node(allocator, child);
                allocator.free(children);
            }

            children[0] = try build_node(allocator, key, 0);
            initialized = 1;
            const value_alignment = try canonical_alignment(value);
            const value_offset = align_up(children[0].provisional_size, value_alignment);
            children[1] = try build_node(allocator, value, value_offset);
            initialized = 2;

            return .{
                .kind = .map,
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
                if (field.value.kind() == .record) {
                    children[initialized].record_type_name = try allocator.dupe(u8, field.name);
                }
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
        .option => try build_variant_node(allocator, source, .option),
        .result => try build_variant_node(allocator, source, .result),
        .variant => try build_variant_node(allocator, source, .variant),
        .resource => error.ResourceBoundaryUnsupported,
        .unit, .tuple => error.UnsupportedMarshalShape,
    };
}

fn build_variant_node(
    allocator: std.mem.Allocator,
    source: *const wit_types.AbiType,
    kind: NodeKind,
) anyerror!MarshalNode {
    const case_count = switch (kind) {
        .option => 2,
        .result => 2,
        .variant => source.variant_case_count() orelse return error.UnsupportedMarshalShape,
        else => return error.UnsupportedMarshalShape,
    };
    var cases = try allocator.alloc(VariantCase, case_count);
    var children = try allocator.alloc(MarshalNode, payload_count(source, kind));
    var initialized_cases: usize = 0;
    var initialized_children: usize = 0;
    errdefer {
        for (children[0..initialized_children]) |child| deinit_node(allocator, child);
        allocator.free(children);
        for (cases[0..initialized_cases]) |*case| allocator.free(case.name);
        allocator.free(cases);
    }

    for (0..case_count) |index| {
        const source_case = variant_case(source, kind, index) orelse return error.UnsupportedMarshalShape;
        const payload_child = if (source_case.payload != null) blk: {
            const child_index = initialized_children;
            children[child_index] = try build_node(allocator, source_case.payload.?, 4);
            initialized_children += 1;
            break :blk @as(?usize, child_index);
        } else null;
        cases[index] = .{
            .name = try allocator.dupe(u8, source_case.name),
            .tag = source_case.tag,
            .payload_child = payload_child,
        };
        initialized_cases += 1;
    }

    return .{
        .kind = kind,
        .canonical_shape = .aggregate,
        .provisional_offset = 0,
        .provisional_size = variant_provisional_size(children),
        .provisional_alignment = 4,
        .children = children,
        .variant_cases = cases,
    };
}

fn payload_count(source: *const wit_types.AbiType, kind: NodeKind) usize {
    return switch (kind) {
        .option => if (source.option_value() != null) 1 else 0,
        .result => @as(usize, @intFromBool(source.result_ok() != null)) + @as(usize, @intFromBool(source.result_err() != null)),
        .variant => blk: {
            var count: usize = 0;
            for (0..source.variant_case_count().?) |index| {
                if (source.variant_case_at(index).?.payload != null) count += 1;
            }
            break :blk count;
        },
        else => 0,
    };
}

fn variant_case(source: *const wit_types.AbiType, kind: NodeKind, index: usize) ?wit_types.VariantCaseRef {
    return switch (kind) {
        .option => if (index == 0)
            .{ .tag = 0, .name = "none", .payload = null }
        else if (index == 1)
            .{ .tag = 1, .name = "some", .payload = source.option_value() }
        else null,
        .result => if (index == 0)
            .{ .tag = 0, .name = "ok", .payload = source.result_ok() }
        else if (index == 1)
            .{ .tag = 1, .name = "err", .payload = source.result_err() }
        else null,
        .variant => source.variant_case_at(index),
        else => null,
    };
}

fn variant_provisional_size(children: []const MarshalNode) u32 {
    var size: u32 = 4;
    for (children) |child| size = @max(size, align_up(4, child.provisional_alignment) + child.provisional_size);
    return size;
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
            try bind_measured_list_element(&node.children[0], element, measured.children[0], facts.ticket_offset);
            node.measured = .{
                .offset = placement_offset orelse 0,
                .byte_size = 8,
                .alignment = 4,
                .element_stride = facts.element_stride,
                .element_byte_size = facts.element_byte_size,
                .element_alignment = facts.element_alignment,
                .capacity = facts.capacity,
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
                .element_byte_size = facts.element_byte_size,
                .element_alignment = facts.element_alignment,
                .capacity = facts.capacity,
                .pointer_offset = facts.pointer_offset,
                .length_offset = facts.length_offset,
            };
        },
        .map => |facts| {
            if (source.kind() != .map) return error.MeasuredKindMismatch;
            var layout = try wit_layout.MapLayoutPlan.init(allocator, source, facts);
            defer layout.deinit();
            if (measured.children.len != 2 or node.children.len != 2) return error.MeasuredChildCountMismatch;
            const key = source.map_key() orelse return error.UnsupportedMeasuredShape;
            const value = source.map_value() orelse return error.UnsupportedMeasuredShape;
            try bind_measured_node(allocator, &node.children[0], key, measured.children[0], facts.key.offset);
            try bind_measured_node(allocator, &node.children[1], value, measured.children[1], facts.value.offset);
            const key_facts = node.children[0].measured orelse return error.MeasuredChildMissing;
            const value_facts = node.children[1].measured orelse return error.MeasuredChildMissing;
            if (key_facts.byte_size != facts.key.byte_size or key_facts.alignment != facts.key.alignment or
                value_facts.byte_size != facts.value.byte_size or value_facts.alignment != facts.value.alignment)
            {
                return error.MeasuredFieldMismatch;
            }
            node.measured = .{
                .offset = placement_offset orelse 0,
                .byte_size = 8,
                .alignment = 4,
                .element_stride = facts.element_stride,
                .element_byte_size = facts.element_byte_size,
                .element_alignment = facts.element_alignment,
                .capacity = facts.capacity,
                .pointer_offset = facts.pointer_offset,
                .length_offset = facts.length_offset,
                .map_key_offset = facts.key.offset,
                .map_value_offset = facts.value.offset,
                .map_pair_byte_size = facts.element_byte_size,
                .map_pair_alignment = facts.element_alignment,
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
        .variant => |facts| {
            if (source.kind() != .option and source.kind() != .result and source.kind() != .variant) {
                return error.MeasuredKindMismatch;
            }
            var layout = try wit_layout.LayoutPlan.variant(allocator, source, facts);
            defer layout.deinit();
            if (facts.cases.len != node.variant_cases.len or measured.children.len != node.children.len) {
                return error.MeasuredChildCountMismatch;
            }
            node.variant_tag_offset = std.math.add(u32, placement_offset orelse 0, facts.tag_offset) catch return error.OffsetOverflow;
            for (facts.cases, 0..) |measured_case, index| {
                const source_case = variant_case(source, node.kind, index) orelse return error.UnsupportedMeasuredShape;
                const node_case = &node.variant_cases[index];
                if (!std.mem.eql(u8, source_case.name, measured_case.name) or source_case.tag != measured_case.tag) {
                    return error.MeasuredFieldMismatch;
                }
                if ((source_case.payload != null) != measured_case.payload_required or
                    (measured_case.payload != null) != (node_case.payload_child != null))
                {
                    return error.MeasuredChildCountMismatch;
                }
                if (measured_case.payload) |payload| {
                    const child_index = node_case.payload_child orelse return error.MeasuredChildMissing;
                    const payload_offset = std.math.add(u32, placement_offset orelse 0, payload.offset) catch return error.OffsetOverflow;
                    try bind_measured_node(allocator, &node.children[child_index], source_case.payload.?, measured.children[child_index], payload_offset);
                    const child_facts = node.children[child_index].measured orelse return error.MeasuredChildMissing;
                    if (child_facts.byte_size != payload.byte_size or child_facts.alignment != payload.alignment) {
                        return error.MeasuredFieldMismatch;
                    }
                    node_case.payload_offset = payload_offset;
                    node_case.payload_byte_size = payload.byte_size;
                    node_case.payload_alignment = payload.alignment;
                    node_case.payload_core_type = payload.core_type;
                }
            }
            node.measured = .{
                .offset = placement_offset orelse 0,
                .byte_size = facts.byte_size,
                .alignment = facts.alignment,
            };
        },
    }
}

fn bind_measured_list_element(
    node: *MarshalNode,
    source: *const wit_types.AbiType,
    measured: MeasuredNode,
    placement_offset: u32,
) !void {
    if (source.kind() != .scalar or measured.children.len != 0) return error.UnsupportedMeasuredShape;
    const facts = switch (measured.layout) {
        .scalar => |value| value,
        else => return error.MeasuredKindMismatch,
    };
    const expected = wit_layout.scalar_list_element_measurement(source.scalar_kind() orelse return error.UnsupportedMeasuredShape);
    if (facts.byte_size != expected.byte_size or facts.alignment != expected.alignment or
        facts.core_type != expected.core_type or facts.offset != 0)
    {
        return error.MeasuredFieldMismatch;
    }
    node.measured = .{
        .offset = placement_offset,
        .byte_size = facts.byte_size,
        .alignment = facts.alignment,
        .core_type = facts.core_type,
    };
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
        .text, .list, .map => 4,
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
        .option, .result, .variant => 4,
        .resource => error.ResourceBoundaryUnsupported,
        .unit, .tuple => error.UnsupportedMarshalShape,
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
    if (node.record_type_name) |name| allocator.free(name);
    for (node.variant_cases) |*case| allocator.free(case.name);
    if (node.variant_cases.len != 0) allocator.free(node.variant_cases);
}

test "marshal plan represents map as a pair-list node" {
    var key = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer key.deinit();
    var value = wit_types.AbiType.text(std.testing.allocator);
    defer value.deinit();
    var source = try wit_types.AbiType.map(std.testing.allocator, &key, &value);
    defer source.deinit();

    const plan = try build_sync_value_plan(std.testing.allocator, .{
        .package = "demo:marshal-map@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    }, &source, .lower);
    defer deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(NodeKind.map, plan.root.kind);
    try std.testing.expectEqual(CanonicalShape.ptr_len, plan.root.canonical_shape);
    try std.testing.expectEqual(@as(usize, 2), plan.root.children.len);
    try std.testing.expectEqual(NodeKind.scalar, plan.root.children[0].kind);
    try std.testing.expectEqual(NodeKind.text, plan.root.children[1].kind);
    try std.testing.expectEqualStrings("map", plan.abi.arguments[0].source_type);
    try std.testing.expectEqualStrings("(i32,i32)", plan.abi.arguments[0].canonical_type);
}

test "marshal plan builds option and result variant nodes" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var optional = try wit_types.AbiType.option(std.testing.allocator, &value);
    defer optional.deinit();
    var text = wit_types.AbiType.text(std.testing.allocator);
    defer text.deinit();
    var result = try wit_types.AbiType.result(std.testing.allocator, &text, &value);
    defer result.deinit();

    const option_plan = try build_sync_value_plan(std.testing.allocator, .{
        .package = "demo:marshal-option@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    }, &optional, .lower);
    defer deinit_sync_value_plan(std.testing.allocator, option_plan);
    try std.testing.expectEqual(NodeKind.option, option_plan.root.kind);
    try std.testing.expectEqual(@as(usize, 1), option_plan.root.children.len);
    try std.testing.expectEqual(@as(usize, 2), option_plan.root.variant_cases.len);
    try std.testing.expectEqual(@as(?usize, null), option_plan.root.variant_cases[0].payload_child);
    try std.testing.expectEqual(@as(?usize, 0), option_plan.root.variant_cases[1].payload_child);

    const result_plan = try build_sync_value_plan(std.testing.allocator, .{
        .package = "demo:marshal-result@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    }, &result, .lower);
    defer deinit_sync_value_plan(std.testing.allocator, result_plan);
    try std.testing.expectEqual(NodeKind.result, result_plan.root.kind);
    try std.testing.expectEqual(@as(usize, 2), result_plan.root.children.len);
    try std.testing.expectEqual(@as(?usize, 0), result_plan.root.variant_cases[0].payload_child);
    try std.testing.expectEqual(@as(?usize, 1), result_plan.root.variant_cases[1].payload_child);
    try std.testing.expectEqual(NodeKind.text, result_plan.root.children[0].kind);
    try std.testing.expectEqual(NodeKind.scalar, result_plan.root.children[1].kind);
}

test "marshal plan binds measured variant payload children" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var optional = try wit_types.AbiType.option(std.testing.allocator, &value);
    defer optional.deinit();

    const plan = try build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-option-measured@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    }, &optional, .lift, .{
        .layout = .{ .variant = .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{
                .{ .name = "none", .tag = 0, .payload_required = false, .payload = null },
                .{ .name = "some", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        } },
        .children = &.{.{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .core_type = .i32,
        } } }},
    });
    defer deinit_sync_value_plan(std.testing.allocator, plan);
    try std.testing.expectEqual(NodeKind.option, plan.root.kind);
    try std.testing.expectEqual(@as(u32, 0), plan.root.variant_tag_offset);
    try std.testing.expectEqual(@as(?u32, 4), plan.root.variant_cases[1].payload_offset);
    try std.testing.expectEqual(@as(?u32, 4), plan.root.children[0].measured.?.offset);
}

test "marshal plan rejects variant measurement drift and unsupported payloads" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var optional = try wit_types.AbiType.option(std.testing.allocator, &value);
    defer optional.deinit();

    const drift = build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-option-drift@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    }, &optional, .lift, .{
        .layout = .{ .variant = .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{
                .{ .name = "empty", .tag = 0, .payload_required = false, .payload = null },
                .{ .name = "some", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        } },
        .children = &.{.{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .core_type = .i32,
        } } }},
    });
    try std.testing.expectError(error.MissingPayloadMetadata, drift);

    const invalid_offset = build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-option-offset@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:9999999999999999999999999999999999999999999999999999999999999999",
    }, &optional, .lift, .{
        .layout = .{ .variant = .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{
                .{ .name = "none", .tag = 0, .payload_required = false, .payload = null },
                .{ .name = "some", .tag = 1, .payload_required = true, .payload = .{ .offset = 2, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        } },
        .children = &.{.{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .core_type = .i32,
        } } }},
    });
    try std.testing.expectError(error.MisalignedOffset, invalid_offset);

    var resource = try wit_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer resource.deinit();
    var resource_option = try wit_types.AbiType.option(std.testing.allocator, &resource);
    defer resource_option.deinit();
    try std.testing.expectError(
        error.ResourceBoundaryUnsupported,
        build_sync_value_plan(std.testing.allocator, .{
            .package = "demo:marshal-resource-option@1.0.0",
            .world = "probe",
            .member = "api.read",
            .revision = "wit-resolver-v1",
            .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }, &resource_option, .lower),
    );
}
