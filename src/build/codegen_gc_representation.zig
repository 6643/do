//! Pure source-shape classification for the Wasm GC backend.
const std = @import("std");
const type_name = @import("type_name.zig");

pub const ValueRep = enum {
    inline_value,
    gc_managed,
    resource_handle,
};

pub const StructFieldShape = struct {
    name: []const u8,
    ty: []const u8,
};

pub const StructShape = struct {
    name: []const u8,
    fields: []const StructFieldShape,
};

pub const ClassifyError = error{
    UnknownType,
    ResourceInManagedAggregate,
    UnsupportedGcAggregate,
};

pub fn classify_type(
    ty: []const u8,
    structs: []const StructShape,
    resources: []const []const u8,
) ClassifyError!ValueRep {
    return classify_type_with_stack(ty, structs, resources, &.{});
}

fn classify_type_with_stack(
    ty: []const u8,
    structs: []const StructShape,
    resources: []const []const u8,
    stack: []const []const u8,
) ClassifyError!ValueRep {
    if (contains_name(resources, ty)) return .resource_handle;
    if (std.mem.eql(u8, ty, "nil") or type_name.is_core_wasm_scalar(ty)) return .inline_value;
    if (std.mem.eql(u8, ty, "text")) return .gc_managed;

    if (type_name.storage_elem_type_from_name(ty)) |elem_ty| {
        const elem_rep = try classify_type_with_stack(elem_ty, structs, resources, stack);
        if (elem_rep == .resource_handle) return error.ResourceInManagedAggregate;
        return .gc_managed;
    }

    if (type_name.is_tuple_type_name(ty)) {
        var has_managed = false;
        const arity = type_name.tuple_arity(ty) orelse return error.UnsupportedGcAggregate;
        var idx: usize = 0;
        while (idx < arity) : (idx += 1) {
            const elem_ty = type_name.tuple_element_type_at(ty, idx) orelse return error.UnsupportedGcAggregate;
            const elem_rep = try classify_type_with_stack(elem_ty, structs, resources, stack);
            if (elem_rep == .resource_handle) return error.ResourceInManagedAggregate;
            has_managed = has_managed or elem_rep == .gc_managed;
        }
        return if (has_managed) .gc_managed else .inline_value;
    }

    const shape = find_struct(structs, ty) orelse return error.UnknownType;
    if (contains_name(stack, shape.name)) return error.UnsupportedGcAggregate;

    var next_stack: [64][]const u8 = undefined;
    if (stack.len >= next_stack.len) return error.UnsupportedGcAggregate;
    std.mem.copyForwards([]const u8, next_stack[0..stack.len], stack);
    next_stack[stack.len] = shape.name;
    const nested_stack = next_stack[0 .. stack.len + 1];
    var has_managed = false;
    for (shape.fields) |field| {
        const field_rep = try classify_type_with_stack(field.ty, structs, resources, nested_stack);
        if (field_rep == .resource_handle) return error.ResourceInManagedAggregate;
        has_managed = has_managed or field_rep == .gc_managed;
    }
    return if (has_managed) .gc_managed else .inline_value;
}

fn find_struct(structs: []const StructShape, name: []const u8) ?StructShape {
    for (structs) |shape| {
        if (std.mem.eql(u8, shape.name, name)) return shape;
    }
    return null;
}

fn contains_name(names: []const []const u8, target: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, target)) return true;
    }
    return false;
}
