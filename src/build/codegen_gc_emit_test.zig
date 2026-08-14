const std = @import("std");
const emit = @import("codegen_gc_emit.zig");

test "GC fragments compose in one module with one shared prelude" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);

    var module = emit.GcModuleEmitter.init(std.testing.allocator, &out);
    try module.begin();
    try module.emit_text_identity(.{ .function_name = "identity", .value_name = "value" });
    try module.emit_text_identity(.{ .function_name = "relay", .value_name = "message" });
    try module.end();

    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "(module\n"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "(type $do_bytes"));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(func $identity") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(func $relay") != null);
}

test "shared GC emitter writes text identity with typed references" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_text_identity(std.testing.allocator, &out, .{ .function_name = "identity", .value_name = "value" });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(param $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "__arc_") == null);
}

test "shared GC emitter does not expose parameterized list template" {
    try std.testing.expect(!@hasDecl(emit, "emit_parameterized_byte_list_set"));
}

test "shared GC emitter does not expose fixed list template" {
    try std.testing.expect(!@hasDecl(emit, "emit_byte_list_set"));
}

test "shared GC emitter rebuilds managed struct and preserves scalar field" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_managed_struct_set(std.testing.allocator, &out, .{
        .scalar_field = .{ .source_field_name = "tag" },
    });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "(type $box (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(field $tag i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $box $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.len") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.const 3\n    array.copy") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "__arc_") == null);
}

test "shared GC emitter retains managed struct source bindings" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_managed_struct_set(std.testing.allocator, &out, .{
        .managed_field = .{ .source_type_name = "Packet", .source_field_name = "bytes" },
        .scalar_field = .{ .source_type_name = "Packet", .source_field_name = "version" },
        .function_binding = .{ .source_name = "rewrite", .receiver_name = "packet" },
    });

    try std.testing.expect(std.mem.indexOf(u8, out.items, "(type $packet (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "(func $rewrite (param $packet") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $packet $bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $packet $version") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "$box") == null);
}

test "managed struct plan retains explicit source bindings after renamed lowering" {
    const plan = emit.ManagedStructSetPlan{
        .managed_field = .{ .source_type_name = "Packet", .source_field_name = "bytes" },
        .scalar_field = .{ .source_type_name = "Packet", .source_field_name = "version" },
        .function_binding = .{ .source_name = "rewrite", .receiver_name = "packet" },
    };
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_managed_struct_set(std.testing.allocator, &out, plan);

    try std.testing.expectEqualStrings("Packet", plan.managed_field.source_type_name);
    try std.testing.expectEqualStrings("bytes", plan.managed_field.source_field_name);
    try std.testing.expectEqualStrings("Packet", plan.scalar_field.?.source_type_name);
    try std.testing.expectEqualStrings("version", plan.scalar_field.?.source_field_name);
    try std.testing.expectEqualStrings("rewrite", plan.function_binding.source_name);
    try std.testing.expectEqualStrings("packet", plan.function_binding.receiver_name);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $packet $bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $packet $version") != null);
}

test "shared GC emitter rebuilds managed tuple and preserves text field" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_managed_tuple_set(std.testing.allocator, &out, .{});

    try std.testing.expect(std.mem.indexOf(u8, out.items, "(type $tuple_text_bytes (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $tuple_text_bytes $text") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.new $tuple_text_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "__arc_") == null);
}

test "GC nested-list copy checks runtime length and never hardcodes three" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit.emit_managed_tuple_set(std.testing.allocator, &out, .{});

    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.len\n    local.set $__gc_length") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.get $__gc_length\n    i32.eqz\n    if unreachable end") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.const 3\n    array.copy") == null);
}
