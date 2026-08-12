//! Core GC type prelude assembly.
const std = @import("std");
const runtime_gc_wat = @import("runtime_gc_wat.zig");
const gc_layout = @import("codegen_gc_layout.zig");
const type_name = @import("type_name.zig");

pub fn emit_bytes_prelude(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try runtime_gc_wat.emit_bytes_type(allocator, out);
}

pub fn emit_text_prelude(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try runtime_gc_wat.emit_bytes_type(allocator, out);
    try runtime_gc_wat.emit_text_type(allocator, out);
}

pub fn emit_managed_struct_prelude(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    has_scalar_field: bool,
) !void {
    try runtime_gc_wat.emit_bytes_type(allocator, out);
    try runtime_gc_wat.emit_box_type(allocator, out, has_scalar_field);
}

pub fn emit_named_managed_struct_prelude(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    struct_name: []const u8,
    value_field_name: []const u8,
    scalar_field_name: ?[]const u8,
) !void {
    try emit_bytes_prelude(allocator, out);
    try runtime_gc_wat.emit_managed_struct_type(allocator, out, struct_name, value_field_name, scalar_field_name);
}

pub fn emit_managed_tuple_prelude(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try emit_text_prelude(allocator, out);
    try runtime_gc_wat.emit_tuple_text_bytes_type(allocator, out);
}

pub fn emit_gc_struct_prelude(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layouts: []const gc_layout.GcStructLayout,
) !void {
    try emit_text_prelude(allocator, out);
    try validate_layout_names(layouts);

    const emitted = try allocator.alloc(bool, layouts.len);
    defer allocator.free(emitted);
    @memset(emitted, false);

    const visiting = try allocator.alloc(bool, layouts.len);
    defer allocator.free(visiting);
    @memset(visiting, false);

    for (layouts, 0..) |_, index| {
        try emit_layout_depth_first(allocator, out, layouts, emitted, visiting, index);
    }
}

fn emit_layout_depth_first(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layouts: []const gc_layout.GcStructLayout,
    emitted: []bool,
    visiting: []bool,
    index: usize,
) !void {
    if (emitted[index]) return;
    if (visiting[index]) return error.UnsupportedGcSyncType;
    visiting[index] = true;
    defer visiting[index] = false;

    for (layouts[index].fields) |field| {
        if (field.rep != .gc_managed or gc_layout.leaf_layout_for_type(field.ty) != null) continue;
        const dependency = find_layout_index(layouts, field.ty) orelse return error.UnsupportedGcSyncType;
        try emit_layout_depth_first(allocator, out, layouts, emitted, visiting, dependency);
    }

    try runtime_gc_wat.emit_gc_struct_type(allocator, out, layouts[index]);
    emitted[index] = true;
}

fn find_layout_index(layouts: []const gc_layout.GcStructLayout, name: []const u8) ?usize {
    for (layouts, 0..) |layout, index| {
        if (std.mem.eql(u8, layout.name, name)) return index;
    }
    return null;
}

fn validate_layout_names(layouts: []const gc_layout.GcStructLayout) !void {
    for (layouts, 0..) |layout, index| {
        for (layouts[0..index]) |previous| {
            if (lowered_name_equal(layout.name, previous.name)) return error.UnsupportedGcSyncType;
        }
        for (layout.fields) |field| {
            if (field.rep == .inline_value and !type_name.is_core_wasm_scalar(field.ty)) {
                return error.UnsupportedGcSyncType;
            }
            if (field.rep == .resource_handle) return error.UnsupportedGcSyncType;
            if (field.rep == .gc_managed and gc_layout.leaf_layout_for_type(field.ty) == null and
                find_layout_index(layouts, field.ty) == null)
            {
                return error.UnsupportedGcSyncType;
            }
        }
    }
}

fn lowered_name_equal(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_ch, right_ch| {
        if (std.ascii.toLower(left_ch) != std.ascii.toLower(right_ch)) return false;
    }
    return true;
}

test "GC struct prelude orders nested managed dependencies" {
    const fields_outer = [_]gc_layout.GcFieldLayout{
        .{ .name = "inner", .ty = "Inner", .rep = .gc_managed, .field_index = 0 },
    };
    const fields_inner = [_]gc_layout.GcFieldLayout{
        .{ .name = "value", .ty = "[u8]", .rep = .gc_managed, .field_index = 0 },
    };
    const layouts = [_]gc_layout.GcStructLayout{
        .{ .name = "Outer", .fields = fields_outer[0..] },
        .{ .name = "Inner", .fields = fields_inner[0..] },
    };
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit_gc_struct_prelude(std.testing.allocator, &out, layouts[0..]);
    const inner = std.mem.indexOf(u8, out.items, "(type $inner ") orelse return error.TestExpectedEqual;
    const outer = std.mem.indexOf(u8, out.items, "(type $outer ") orelse return error.TestExpectedEqual;
    try std.testing.expect(inner < outer);
}
