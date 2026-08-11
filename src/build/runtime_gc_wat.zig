//! Shared Core Wasm GC type fragments.
const std = @import("std");

pub fn emit_bytes_type(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(allocator, "  (type $do_bytes (array (mut i8)))\n");
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

pub fn emit_tuple_text_bytes_type(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(allocator, "  (type $tuple_text_bytes (struct (field $text (ref null $do_text)) (field $bytes (ref null $do_bytes))))\n");
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
