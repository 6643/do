//! Adapter from collected compiler declarations to pure GC representation facts.
const std = @import("std");
const model = @import("codegen_model.zig");
const representation = @import("codegen_gc_representation.zig");
const gc_layout = @import("codegen_gc_layout.zig");

pub fn collect_struct_layout(
    allocator: std.mem.Allocator,
    decl: model.StructDecl,
    decls: []const model.StructDecl,
    resources: []const []const u8,
) !gc_layout.GcStructLayout {
    var shapes = try allocator.alloc(representation.StructShape, decls.len);
    errdefer allocator.free(shapes);

    var field_shapes = try allocator.alloc([]representation.StructFieldShape, decls.len);
    errdefer allocator.free(field_shapes);

    var initialized: usize = 0;
    errdefer {
        for (field_shapes[0..initialized]) |fields| allocator.free(fields);
    }

    for (decls, 0..) |source, index| {
        const fields = try allocator.alloc(representation.StructFieldShape, source.fields.len);
        field_shapes[index] = fields;
        initialized += 1;
        for (source.fields, 0..) |field, field_index| {
            fields[field_index] = .{ .name = field.name, .ty = field.ty };
        }
        shapes[index] = .{ .name = source.name, .fields = fields };
    }

    const target = find_shape(shapes, decl.name) orelse return error.UnknownType;
    const result = try gc_layout.collect_struct_layout(allocator, target, shapes, resources);

    for (field_shapes) |fields| allocator.free(fields);
    allocator.free(field_shapes);
    allocator.free(shapes);
    return result;
}

pub fn deinit_struct_layout(allocator: std.mem.Allocator, layout: gc_layout.GcStructLayout) void {
    gc_layout.deinit_struct_layout(allocator, layout);
}

pub fn collect_struct_shapes(
    allocator: std.mem.Allocator,
    decls: []const model.StructDecl,
) ![]representation.StructShape {
    const shapes = try allocator.alloc(representation.StructShape, decls.len);
    errdefer allocator.free(shapes);

    var initialized: usize = 0;
    errdefer {
        for (shapes[0..initialized]) |shape| allocator.free(@constCast(shape.fields));
    }

    for (decls, 0..) |source, index| {
        const fields = try allocator.alloc(representation.StructFieldShape, source.fields.len);
        initialized += 1;
        for (source.fields, 0..) |field, field_index| {
            fields[field_index] = .{ .name = field.name, .ty = field.ty };
        }
        shapes[index] = .{ .name = source.name, .fields = fields };
    }
    return shapes;
}

pub fn deinit_struct_shapes(allocator: std.mem.Allocator, shapes: []representation.StructShape) void {
    for (shapes) |shape| allocator.free(@constCast(shape.fields));
    allocator.free(shapes);
}

fn find_shape(shapes: []const representation.StructShape, name: []const u8) ?representation.StructShape {
    for (shapes) |shape| {
        if (std.mem.eql(u8, shape.name, name)) return shape;
    }
    return null;
}
