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
    const rep = representation.classify_type(ty, structs, &.{}) catch return error.UnsupportedGcSyncType;
    const leaf_layout = layout.leaf_layout_for_type(ty);
    if (rep == .resource_handle) return error.UnsupportedGcSyncType;
    const aggregate_layout = if (rep == .gc_managed and leaf_layout == null)
        find_struct_layout(layouts, ty) orelse return error.UnsupportedGcSyncType
    else
        null;

    const wasm_type = if (leaf_layout) |leaf| switch (leaf) {
        .text => "(ref null $do_text)",
        .byte_array => "(ref null $do_bytes)",
    } else if (aggregate_layout != null) "(ref null $gc_struct)" else try scalar_wasm_type(ty);
    return .{ .rep = rep, .layout = leaf_layout, .aggregate_layout = aggregate_layout, .wasm_type = wasm_type };
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
    const facts = try classify_admitted_type_with_layouts(ty, structs, layouts);
    if (facts.aggregate_layout) |aggregate| {
        try out.appendSlice(allocator, "(ref null $");
        for (aggregate.name) |ch| try out.append(allocator, std.ascii.toLower(ch));
        try out.append(allocator, ')');
        return;
    }
    try out.appendSlice(allocator, facts.wasm_type);
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
