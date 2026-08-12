//! Core GC type prelude assembly.
const std = @import("std");
const runtime_gc_wat = @import("runtime_gc_wat.zig");
const gc_layout = @import("codegen_gc_layout.zig");

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
    for (layouts) |layout| try runtime_gc_wat.emit_gc_struct_type(allocator, out, layout);
}
