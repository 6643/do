//! Shared Core Wasm GC type fragments.
const std = @import("std");
const gc_layout = @import("codegen_gc_layout.zig");
const payload_wat = @import("wat_payload.zig");

pub fn emit_bytes_type(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(allocator, "  (type $do_bytes (array (mut i8)))\n");
}

pub fn emit_scalar_array_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    array_name: []const u8,
    elem_ty: []const u8,
) !void {
    try append_fmt(allocator, out, "  (type {s} (array (mut {s})))\n", .{ array_name, payload_wat.wasm_type(elem_ty) });
}

pub fn emit_managed_array_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    array_name: []const u8,
    elem_ty: []const u8,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) !void {
    try append_fmt(allocator, out, "  (type {s} (array (mut (ref null $", .{array_name});
    if (std.mem.eql(u8, elem_ty, "text")) {
        try out.appendSlice(allocator, "do_text");
    } else if (std.mem.eql(u8, elem_ty, "[u8]")) {
        try out.appendSlice(allocator, "do_bytes");
    } else if (gc_layout.scalar_array_spec_for_type(elem_ty)) |spec| {
        try out.appendSlice(allocator, spec.array_name[1..]);
    } else {
        var found_managed_array = false;
        for (managed_arrays) |managed_array| {
            if (std.mem.eql(u8, managed_array.list_ty, elem_ty)) {
                try out.appendSlice(allocator, managed_array.array_name[1..]);
                found_managed_array = true;
                break;
            }
        }
        if (!found_managed_array) try append_lowered_name(allocator, out, elem_ty);
    }
    try out.appendSlice(allocator, "))))\n");
}

pub fn emit_u32_type(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try emit_scalar_array_type(allocator, out, "$do_u32", "u32");
}

pub fn emit_text_type(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(allocator, "  (type $do_text (struct (field $length i32) (field $bytes (ref null $do_bytes))))\n");
}

pub fn emit_box_type(allocator: std.mem.Allocator, out: *std.ArrayList(u8), has_scalar_field: bool) !void {
    if (has_scalar_field) {
        try out.appendSlice(allocator, "  (type $box (struct (field $value (ref null $do_bytes)) (field $tag i32)))\n");
        return;
    }
    try out.appendSlice(allocator, "  (type $box (struct (field $value (ref null $do_bytes))))\n");
}

pub fn emit_managed_struct_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    struct_name: []const u8,
    value_field_name: []const u8,
    scalar_field_name: ?[]const u8,
) !void {
    if (scalar_field_name) |field_name| {
        try append_fmt(allocator, out, "  (type ${s} (struct (field ${s} (ref null $do_bytes)) (field ${s} i32)))\n", .{ struct_name, value_field_name, field_name });
        return;
    }
    try append_fmt(allocator, out, "  (type ${s} (struct (field ${s} (ref null $do_bytes))))\n", .{ struct_name, value_field_name });
}

pub fn emit_gc_struct_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layout: gc_layout.GcStructLayout,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) !void {
    try out.appendSlice(allocator, "  (type $");
    try append_lowered_name(allocator, out, layout.name);
    try out.appendSlice(allocator, " (struct");
    var field_index: u32 = 0;
    while (field_index < layout.fields.len) : (field_index += 1) {
        const field = find_field_by_index(layout.fields, field_index) orelse return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, " (field ${s} ", .{field.name});
        try append_gc_field_wasm_type(allocator, out, field, managed_arrays);
        try out.append(allocator, ')');
    }
    try out.appendSlice(allocator, "))\n");
}

fn find_field_by_index(fields: []const gc_layout.GcFieldLayout, field_index: u32) ?gc_layout.GcFieldLayout {
    for (fields) |field| {
        if (field.field_index == field_index) return field;
    }
    return null;
}

fn append_gc_field_wasm_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    field: gc_layout.GcFieldLayout,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) !void {
    if (field.rep == .inline_value) {
        try out.appendSlice(allocator, payload_wat.wasm_type(field.ty));
        return;
    }
    if (std.mem.eql(u8, field.ty, "text")) {
        try out.appendSlice(allocator, "(ref null $do_text)");
        return;
    }
    if (std.mem.eql(u8, field.ty, "[u8]")) {
        try out.appendSlice(allocator, "(ref null $do_bytes)");
        return;
    }
    if (gc_layout.scalar_array_spec_for_type(field.ty)) |spec| {
        try out.appendSlice(allocator, "(ref null ");
        try out.appendSlice(allocator, spec.array_name);
        try out.append(allocator, ')');
        return;
    }
    for (managed_arrays) |managed_array| {
        if (std.mem.eql(u8, field.ty, managed_array.list_ty)) {
            try out.appendSlice(allocator, "(ref null ");
            try out.appendSlice(allocator, managed_array.array_name);
            try out.append(allocator, ')');
            return;
        }
    }
    if (field.rep != .gc_managed) return error.UnsupportedGcSyncType;
    try out.appendSlice(allocator, "(ref null $");
    try append_lowered_name(allocator, out, field.ty);
    try out.append(allocator, ')');
}

fn append_lowered_name(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    for (name) |ch| try out.append(allocator, std.ascii.toLower(ch));
}

pub fn emit_tuple_text_bytes_type(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(allocator, "  (type $tuple_text_bytes (struct (field $text (ref null $do_text)) (field $bytes (ref null $do_bytes))))\n");
}

pub fn emit_gc_payload_union_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layout: gc_layout.GcPayloadUnionLayout,
) !void {
    try out.appendSlice(allocator, "  (type $");
    try append_lowered_name(allocator, out, layout.name);
    try out.appendSlice(allocator, " (struct (field $tag i32)");
    for (layout.payload_tys, 0..) |payload_ty, index| {
        if (index == layout.managed_payload_index) {
            try out.appendSlice(allocator, " (field $bytes (ref null $do_bytes))");
        } else {
            try append_fmt(allocator, out, " (field $payload_{d} {s})", .{ index, if (gc_layout.leaf_layout_for_type(payload_ty) != null) payload_wat.wasm_type(payload_ty) else "i32" });
        }
    }
    try out.appendSlice(allocator, "))\n");
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime format: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
