//! Pure typed layout facts consumed by GC emitters.
const std = @import("std");
const representation = @import("codegen_gc_representation.zig");
const type_name = @import("type_name.zig");

pub const GcFieldLayout = struct {
    name: []const u8,
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

pub fn collect_struct_layout(
    allocator: std.mem.Allocator,
    shape: representation.StructShape,
    structs: []const representation.StructShape,
    resources: []const []const u8,
) !GcStructLayout {
    var fields = try allocator.alloc(GcFieldLayout, shape.fields.len);
    errdefer allocator.free(fields);

    for (shape.fields, 0..) |field, index| {
        fields[index] = .{
            .name = field.name,
            .rep = try representation.classify_type(field.ty, structs, resources),
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
        fields[index] = .{
            .name = element_ty,
            .rep = try representation.classify_type(element_ty, structs, resources),
            .field_index = @intCast(index),
        };
    }
    return .{ .name = tuple_name, .fields = fields };
}

pub fn deinit_tuple_layout(allocator: std.mem.Allocator, layout: GcTupleLayout) void {
    allocator.free(layout.fields);
}
