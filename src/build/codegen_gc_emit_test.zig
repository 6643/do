const std = @import("std");
const emit = @import("codegen_gc_emit.zig");

test "shared GC emitter writes text identity with typed references" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_text_identity(std.testing.allocator, &out, .{ .function_name = "identity", .value_name = "value" });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(param $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "__arc_") == null);
}

test "shared GC emitter writes immutable byte-list update" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_byte_list_set(std.testing.allocator, &out, .{ .function_name = "update", .input_name = "input", .index_expr = "0", .value_expr = "65" });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "(type $do_bytes (array (mut i8)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "__arc_") == null);
}

test "shared GC emitter preserves parameterized list bindings" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_parameterized_byte_list_set(std.testing.allocator, &out, .{
        .function_name = "set_at",
        .input_name = "bytes",
        .index_name = "offset",
        .value_name = "next",
    });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.get $offset") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.get $next") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.len") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(local $__gc_next (ref $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(local $__gc_length i32)") != null);
}

test "shared GC emitter rebuilds managed struct and preserves scalar field" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_managed_struct_set(std.testing.allocator, &out, .{ .has_scalar_field = true });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "(type $box (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(field $tag i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $box $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "__arc_") == null);
}
