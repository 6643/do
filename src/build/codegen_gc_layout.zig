//! Pure typed layout facts consumed by GC emitters.
const std = @import("std");
const representation = @import("codegen_gc_representation.zig");
const type_name = @import("type_name.zig");

pub const GcFieldLayout = struct {
    name: []const u8,
    ty: []const u8,
    rep: representation.ValueRep,
    field_index: u32,
};

pub const GcStructLayout = struct {
    name: []const u8,
    fields: []const GcFieldLayout,
};

pub const GcTupleLayout = struct {
    name: []const u8,
    fields: []const GcFieldLayout,
};

/// First bounded payload-union carrier admitted by the GC sync migration.
/// The source union has exactly one unit arm and one `[u8]` arm.  The carrier
/// keeps the tag and nullable byte payload in one typed GC object.
pub const GcPayloadUnionLayout = struct {
    name: []const u8,
    unit_case: []const u8,
    managed_case: []const u8,
    unit_tag: u32,
    managed_tag: u32,
};

pub const GcPayloadUnionError = error{
    UnsupportedGcSyncUnionArms,
    UnsupportedGcSyncUnionPayload,
};

pub fn collect_payload_union_layout(name: []const u8, cases: anytype) GcPayloadUnionError!GcPayloadUnionLayout {
    if (cases.len != 2) return error.UnsupportedGcSyncUnionArms;

    var unit_case: ?[]const u8 = null;
    var managed_case: ?[]const u8 = null;
    var unit_tag: u32 = 0;
    var managed_tag: u32 = 0;
    for (cases, 0..) |case, index| {
        const tag: u32 = @intCast(index);
        if (case.payload_ty == null) {
            if (unit_case != null) return error.UnsupportedGcSyncUnionArms;
            unit_case = case.name;
            unit_tag = tag;
            continue;
        }
        if (!std.mem.eql(u8, case.payload_ty.?, "[u8]")) return error.UnsupportedGcSyncUnionPayload;
        if (managed_case != null) return error.UnsupportedGcSyncUnionArms;
        managed_case = case.name;
        managed_tag = tag;
    }

    return .{
        .name = name,
        .unit_case = unit_case orelse return error.UnsupportedGcSyncUnionPayload,
        .managed_case = managed_case orelse return error.UnsupportedGcSyncUnionPayload,
        .unit_tag = unit_tag,
        .managed_tag = managed_tag,
    };
}

/// Runtime layouts currently emitted by the restricted synchronous GC backend.
/// Aggregate layouts are intentionally separate and are not admitted by this
/// adapter until their lowering is wired through this same fact layer.
pub const GcLeafLayout = enum {
    text,
    byte_array,
    scalar_array,
};

pub const ScalarArraySpec = struct {
    list_ty: []const u8,
    elem_ty: []const u8,
    array_name: []const u8,
};

pub const scalar_array_specs = [_]ScalarArraySpec{
    .{ .list_ty = "[bool]", .elem_ty = "bool", .array_name = "$do_bool" },
    .{ .list_ty = "[i8]", .elem_ty = "i8", .array_name = "$do_i8" },
    .{ .list_ty = "[i16]", .elem_ty = "i16", .array_name = "$do_i16" },
    .{ .list_ty = "[i32]", .elem_ty = "i32", .array_name = "$do_i32" },
    .{ .list_ty = "[i64]", .elem_ty = "i64", .array_name = "$do_i64" },
    .{ .list_ty = "[u16]", .elem_ty = "u16", .array_name = "$do_u16" },
    .{ .list_ty = "[u32]", .elem_ty = "u32", .array_name = "$do_u32" },
    .{ .list_ty = "[u64]", .elem_ty = "u64", .array_name = "$do_u64" },
    .{ .list_ty = "[isize]", .elem_ty = "isize", .array_name = "$do_isize" },
    .{ .list_ty = "[usize]", .elem_ty = "usize", .array_name = "$do_usize" },
    .{ .list_ty = "[f32]", .elem_ty = "f32", .array_name = "$do_f32" },
    .{ .list_ty = "[f64]", .elem_ty = "f64", .array_name = "$do_f64" },
};

pub fn scalar_array_spec_for_type(ty: []const u8) ?ScalarArraySpec {
    for (scalar_array_specs) |spec| {
        if (std.mem.eql(u8, spec.list_ty, ty)) return spec;
    }
    return null;
}

pub fn scalar_array_wasm_elem_type(elem_ty: []const u8) []const u8 {
    if (std.mem.eql(u8, elem_ty, "i8") or std.mem.eql(u8, elem_ty, "u8")) return "i32";
    if (std.mem.eql(u8, elem_ty, "i16") or std.mem.eql(u8, elem_ty, "u16")) return "i32";
    if (std.mem.eql(u8, elem_ty, "i32") or std.mem.eql(u8, elem_ty, "u32") or
        std.mem.eql(u8, elem_ty, "isize") or std.mem.eql(u8, elem_ty, "usize") or
        std.mem.eql(u8, elem_ty, "bool")) return "i32";
    if (std.mem.eql(u8, elem_ty, "i64") or std.mem.eql(u8, elem_ty, "u64")) return "i64";
    if (std.mem.eql(u8, elem_ty, "f32")) return "f32";
    if (std.mem.eql(u8, elem_ty, "f64")) return "f64";
    return "i32";
}

pub fn leaf_layout_for_type(ty: []const u8) ?GcLeafLayout {
    if (std.mem.eql(u8, ty, "text")) return .text;
    if (std.mem.eql(u8, ty, "[u8]")) return .byte_array;
    if (scalar_array_spec_for_type(ty) != null) return .scalar_array;
    return null;
}

pub fn collect_struct_layout(
    allocator: std.mem.Allocator,
    shape: representation.StructShape,
    structs: []const representation.StructShape,
    resources: []const []const u8,
) !GcStructLayout {
    var fields = try allocator.alloc(GcFieldLayout, shape.fields.len);
    errdefer allocator.free(fields);

    for (shape.fields, 0..) |field, index| {
        const rep = try representation.classify_type(field.ty, structs, resources);
        if (rep == .resource_handle) return error.ResourceInManagedAggregate;
        fields[index] = .{
            .name = field.name,
            .ty = field.ty,
            .rep = rep,
            .field_index = @intCast(index),
        };
    }
    return .{ .name = shape.name, .fields = fields };
}

pub fn deinit_struct_layout(allocator: std.mem.Allocator, layout: GcStructLayout) void {
    allocator.free(layout.fields);
}

pub fn collect_tuple_layout(
    allocator: std.mem.Allocator,
    tuple_name: []const u8,
    elements: []const []const u8,
    structs: []const representation.StructShape,
    resources: []const []const u8,
) !GcTupleLayout {
    if (elements.len == 0) return error.UnsupportedGcAggregate;

    var fields = try allocator.alloc(GcFieldLayout, elements.len);
    errdefer allocator.free(fields);

    for (elements, 0..) |element_ty, index| {
        if (type_name.is_tuple_type_name(element_ty)) return error.UnsupportedGcAggregate;
        const rep = try representation.classify_type(element_ty, structs, resources);
        if (rep == .resource_handle) return error.ResourceInManagedAggregate;
        fields[index] = .{
            .name = element_ty,
            .ty = element_ty,
            .rep = rep,
            .field_index = @intCast(index),
        };
    }
    return .{ .name = tuple_name, .fields = fields };
}

pub fn deinit_tuple_layout(allocator: std.mem.Allocator, layout: GcTupleLayout) void {
    allocator.free(layout.fields);
}

test "GC layout rejects a struct with a missing managed child" {
    const fields = [_]representation.StructFieldShape{
        .{ .name = "child", .ty = "Missing" },
    };
    const shapes = [_]representation.StructShape{
        .{ .name = "Outer", .fields = fields[0..] },
    };
    try std.testing.expectError(
        error.UnknownType,
        collect_struct_layout(std.testing.allocator, shapes[0], shapes[0..], &.{}),
    );
}

test "GC layout rejects a direct managed struct cycle" {
    const a_fields = [_]representation.StructFieldShape{
        .{ .name = "next", .ty = "B" },
    };
    const b_fields = [_]representation.StructFieldShape{
        .{ .name = "next", .ty = "A" },
    };
    const shapes = [_]representation.StructShape{
        .{ .name = "A", .fields = a_fields[0..] },
        .{ .name = "B", .fields = b_fields[0..] },
    };
    try std.testing.expectError(
        error.UnsupportedGcAggregate,
        collect_struct_layout(std.testing.allocator, shapes[0], shapes[0..], &.{}),
    );
}

test "GC layout rejects a resource field from a managed struct" {
    const fields = [_]representation.StructFieldShape{
        .{ .name = "ticket", .ty = "Ticket" },
    };
    const shapes = [_]representation.StructShape{
        .{ .name = "Envelope", .fields = fields[0..] },
    };
    const resources = [_][]const u8{"Ticket"};
    try std.testing.expectError(
        error.ResourceInManagedAggregate,
        collect_struct_layout(std.testing.allocator, shapes[0], shapes[0..], resources[0..]),
    );
}

test "GC layout rejects an unknown Tuple leaf" {
    const elements = [_][]const u8{"Missing"};
    const shapes = [_]representation.StructShape{};
    try std.testing.expectError(
        error.UnknownType,
        collect_tuple_layout(std.testing.allocator, "Tuple<Missing>", elements[0..], shapes[0..], &.{}),
    );
}

test "GC layout rejects a nested Tuple leaf" {
    const elements = [_][]const u8{"Tuple<i32,u8>"};
    const shapes = [_]representation.StructShape{};
    try std.testing.expectError(
        error.UnsupportedGcAggregate,
        collect_tuple_layout(std.testing.allocator, "Tuple<Tuple<i32,u8>>", elements[0..], shapes[0..], &.{}),
    );
}

test "scalar GC array packed elements use their wasm stack type" {
    try std.testing.expectEqualStrings("i32", scalar_array_wasm_elem_type("i8"));
    try std.testing.expectEqualStrings("i32", scalar_array_wasm_elem_type("u16"));
    try std.testing.expectEqualStrings("i64", scalar_array_wasm_elem_type("u64"));
    try std.testing.expectEqualStrings("i32", scalar_array_wasm_elem_type("usize"));
}
