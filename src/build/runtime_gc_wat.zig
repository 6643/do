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
