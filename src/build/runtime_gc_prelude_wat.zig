//! Core GC type prelude assembly.
const std = @import("std");
const runtime_gc_wat = @import("runtime_gc_wat.zig");

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
