//! Admission and WAT representation adapter for synchronous GC lowering.
const std = @import("std");
const payload_wat = @import("wat_payload.zig");
const type_name = @import("type_name.zig");
const representation = @import("codegen_gc_representation.zig");
const layout = @import("codegen_gc_layout.zig");

pub const ValueRep = representation.ValueRep;

pub const TypeFacts = struct {
    rep: ValueRep,
    layout: ?layout.GcLeafLayout,
    aggregate_layout: ?*const layout.GcStructLayout = null,
    payload_union_layout: ?*const layout.GcPayloadUnionLayout = null,
    wasm_type: []const u8,
};

pub const Error = error{UnsupportedGcSyncType};

/// Joins source classification with a runtime layout that has an emitter.
/// Managed values without a registered leaf or aggregate emitter fail closed.
pub fn classify_admitted_type(
    ty: []const u8,
    structs: []const representation.StructShape,
) Error!TypeFacts {
    return classify_admitted_type_with_layouts(ty, structs, &.{});
}

pub fn classify_admitted_type_with_layouts(
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
) Error!TypeFacts {
    return classify_admitted_type_with_layouts_and_unions(ty, structs, layouts, &.{});
}

pub fn classify_admitted_type_with_layouts_and_unions(
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
    payload_unions: []const layout.GcPayloadUnionLayout,
) Error!TypeFacts {
    return classify_admitted_type_with_layouts_and_unions_and_arrays(ty, structs, layouts, payload_unions, &.{});
}

pub fn classify_admitted_type_with_layouts_and_unions_and_arrays(
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
    payload_unions: []const layout.GcPayloadUnionLayout,
    managed_arrays: []const layout.GcManagedArrayLayout,
) Error!TypeFacts {
    if (find_payload_union_layout(payload_unions, ty)) |payload_union| {
        return .{
            .rep = .gc_managed,
            .layout = null,
            .aggregate_layout = null,
            .payload_union_layout = payload_union,
            .wasm_type = "",
        };
    }
    const rep = representation.classify_type(ty, structs, &.{}) catch return error.UnsupportedGcSyncType;
    const leaf_layout = layout.leaf_layout_for_type(ty);
    if (rep == .resource_handle) return error.UnsupportedGcSyncType;
    const managed_array = find_managed_array_layout(managed_arrays, ty);
    const is_managed_array = managed_array != null or is_managed_list_type(ty, structs);
    const aggregate_layout = if (rep == .gc_managed and leaf_layout == null and !is_gc_sync_tuple_text_bytes(ty))
        if (!is_managed_array) find_struct_layout(layouts, ty) orelse return error.UnsupportedGcSyncType else null
    else
        null;

    const wasm_type = if (leaf_layout) |leaf| switch (leaf) {
        .text => "(ref null $do_text)",
        .byte_array => "(ref null $do_bytes)",
        .scalar_array => try scalar_array_wasm_type(ty),
    } else if (is_gc_sync_tuple_text_bytes(ty)) "(ref null $tuple_text_bytes)" else if (aggregate_layout != null) "(ref null $gc_struct)" else if (is_managed_array) "" else try scalar_wasm_type(ty);
    return .{ .rep = rep, .layout = leaf_layout, .aggregate_layout = aggregate_layout, .wasm_type = wasm_type };
}

fn scalar_array_wasm_type(ty: []const u8) Error![]const u8 {
    const spec = layout.scalar_array_spec_for_type(ty) orelse return error.UnsupportedGcSyncType;
    if (std.mem.eql(u8, spec.list_ty, "[bool]")) return "(ref null $do_bool)";
    if (std.mem.eql(u8, spec.list_ty, "[i8]")) return "(ref null $do_i8)";
    if (std.mem.eql(u8, spec.list_ty, "[i16]")) return "(ref null $do_i16)";
    if (std.mem.eql(u8, spec.list_ty, "[i32]")) return "(ref null $do_i32)";
    if (std.mem.eql(u8, spec.list_ty, "[i64]")) return "(ref null $do_i64)";
    if (std.mem.eql(u8, spec.list_ty, "[u16]")) return "(ref null $do_u16)";
    if (std.mem.eql(u8, spec.list_ty, "[u32]")) return "(ref null $do_u32)";
    if (std.mem.eql(u8, spec.list_ty, "[u64]")) return "(ref null $do_u64)";
    if (std.mem.eql(u8, spec.list_ty, "[isize]")) return "(ref null $do_isize)";
    if (std.mem.eql(u8, spec.list_ty, "[usize]")) return "(ref null $do_usize)";
    if (std.mem.eql(u8, spec.list_ty, "[f32]")) return "(ref null $do_f32)";
    if (std.mem.eql(u8, spec.list_ty, "[f64]")) return "(ref null $do_f64)";
    return error.UnsupportedGcSyncType;
}

pub fn is_gc_sync_tuple_text_bytes(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "Tuple<text,[u8]>");
}

pub fn is_admitted_managed_type(ty: []const u8) bool {
    const facts = classify_admitted_type(ty, &.{}) catch return false;
    return facts.rep == .gc_managed;
}

pub fn is_admitted_managed_type_with_layouts(
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
) bool {
    const facts = classify_admitted_type_with_layouts(ty, structs, layouts) catch return false;
    return facts.rep == .gc_managed;
}

pub fn is_admitted_managed_type_with_layouts_and_unions(
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
    payload_unions: []const layout.GcPayloadUnionLayout,
) bool {
    const facts = classify_admitted_type_with_layouts_and_unions(ty, structs, layouts, payload_unions) catch return false;
    return facts.rep == .gc_managed;
}

pub fn is_supported_type(ty: []const u8) bool {
    _ = classify_admitted_type(ty, &.{}) catch return false;
    return true;
}

pub fn wasm_type_for(ty: []const u8) Error![]const u8 {
    return (try classify_admitted_type(ty, &.{})).wasm_type;
}

pub fn append_wasm_type_for(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
) anyerror!void {
    return append_wasm_type_for_with_unions(allocator, out, ty, structs, layouts, &.{});
}

pub fn append_wasm_type_for_with_unions(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
    payload_unions: []const layout.GcPayloadUnionLayout,
) anyerror!void {
    return append_wasm_type_for_with_unions_and_arrays(allocator, out, ty, structs, layouts, payload_unions, &.{});
}

pub fn append_wasm_type_for_with_unions_and_arrays(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    structs: []const representation.StructShape,
    layouts: []const layout.GcStructLayout,
    payload_unions: []const layout.GcPayloadUnionLayout,
    managed_arrays: []const layout.GcManagedArrayLayout,
) anyerror!void {
    const facts = try classify_admitted_type_with_layouts_and_unions_and_arrays(ty, structs, layouts, payload_unions, managed_arrays);
    if (facts.payload_union_layout) |payload_union| {
        try out.appendSlice(allocator, "(ref null $");
        try append_lowered_wat_name(allocator, out, payload_union.name);
        try out.append(allocator, ')');
        return;
    }
    if (facts.aggregate_layout) |aggregate| {
        try out.appendSlice(allocator, "(ref null $");
        try append_lowered_wat_name(allocator, out, aggregate.name);
        try out.append(allocator, ')');
        return;
    }
    if (is_managed_list_type(ty, structs)) {
        try append_managed_array_wasm_type(allocator, out, ty, managed_arrays);
        return;
    }
    try out.appendSlice(allocator, facts.wasm_type);
}

fn find_managed_array_layout(layouts: []const layout.GcManagedArrayLayout, list_ty: []const u8) ?*const layout.GcManagedArrayLayout {
    for (layouts) |*item| if (std.mem.eql(u8, item.list_ty, list_ty)) return item;
    return null;
}

pub fn is_managed_struct_list_type(ty: []const u8, structs: []const representation.StructShape) bool {
    const elem_ty = type_name.storage_elem_type_from_name(ty) orelse return false;
    if (layout.scalar_array_spec_for_type(ty) != null or type_name.is_tuple_type_name(elem_ty) or type_name.is_storage_type_name(elem_ty)) return false;
    var is_struct = false;
    for (structs) |shape| {
        if (std.mem.eql(u8, shape.name, elem_ty)) {
            is_struct = true;
            break;
        }
    }
    if (!is_struct) return false;
    return (representation.classify_type(elem_ty, structs, &.{}) catch return false) == .gc_managed;
}

pub fn is_managed_text_list_type(ty: []const u8) bool {
    return std.mem.eql(u8, type_name.storage_elem_type_from_name(ty) orelse return false, "text");
}

pub fn is_managed_list_type(ty: []const u8, structs: []const representation.StructShape) bool {
    const elem_ty = type_name.storage_elem_type_from_name(ty) orelse return false;
    if (layout.scalar_array_spec_for_type(ty) != null or type_name.is_tuple_type_name(elem_ty)) return false;
    if (std.mem.eql(u8, elem_ty, "text")) return true;
    if (is_managed_struct_list_type(ty, structs)) return true;
    if (!type_name.is_storage_type_name(elem_ty)) return false;
    const rep = representation.classify_type(elem_ty, structs, &.{}) catch return false;
    return rep == .gc_managed;
}

fn append_managed_array_wasm_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    list_ty: []const u8,
    managed_arrays: []const layout.GcManagedArrayLayout,
) !void {
    const elem_ty = type_name.storage_elem_type_from_name(list_ty) orelse return error.UnsupportedGcSyncType;
    for (managed_arrays) |managed_array| {
        if (std.mem.eql(u8, managed_array.list_ty, list_ty)) {
            try out.appendSlice(allocator, "(ref null ");
            try out.appendSlice(allocator, managed_array.array_name);
            try out.append(allocator, ')');
            return;
        }
    }
    const array_name = try layout.alloc_managed_array_type_name(allocator, elem_ty);
    defer allocator.free(array_name);
    try out.appendSlice(allocator, "(ref null ");
    try out.appendSlice(allocator, array_name);
    try out.append(allocator, ')');
}

fn find_payload_union_layout(layouts: []const layout.GcPayloadUnionLayout, name: []const u8) ?*const layout.GcPayloadUnionLayout {
    for (layouts) |*item| {
        if (std.mem.eql(u8, item.source_ty, name)) return item;
    }
    return null;
}

fn append_lowered_wat_name(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    for (name) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9')) {
            try out.append(allocator, std.ascii.toLower(ch));
        } else {
            try out.append(allocator, '_');
        }
    }
}

fn scalar_wasm_type(ty: []const u8) Error![]const u8 {
    if (std.mem.eql(u8, ty, "nil")) return "";
    if (type_name.is_core_wasm_scalar(ty)) return payload_wat.wasm_type(ty);
    return error.UnsupportedGcSyncType;
}

fn find_struct_layout(layouts: []const layout.GcStructLayout, name: []const u8) ?*const layout.GcStructLayout {
    for (layouts) |*item| {
        if (std.mem.eql(u8, item.name, name)) return item;
    }
    return null;
}

test "admitted scalar facts keep the inline wasm type" {
    const facts = try classify_admitted_type("u32", &.{});
    try std.testing.expectEqual(ValueRep.inline_value, facts.rep);
    try std.testing.expect(facts.layout == null);
    try std.testing.expectEqualStrings("i32", facts.wasm_type);
}
