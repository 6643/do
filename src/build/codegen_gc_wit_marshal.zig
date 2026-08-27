const std = @import("std");
const generated_text = @import("codegen_text.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");
const lexer = @import("lexer.zig");
const descriptor_loader = @import("codegen_component_descriptor_manifest.zig");
const nested_lift_deeper_probe = @import("gc_marshal_record_nested_lift_deeper_probe.zig");
const nested_lower_deeper_probe = @import("gc_marshal_record_nested_lower_deeper_probe.zig");
const host_boundary = @import("codegen_gc_wit_host_boundary.zig");

pub const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
pub const record_byte_list_lower_descriptor = host_boundary.record_byte_list_lower_descriptor;
pub const record_u32_list_lower_descriptor = host_boundary.record_u32_list_lower_descriptor;
pub const record_two_u32_lists_lower_descriptor = host_boundary.record_two_u32_lists_lower_descriptor;
pub const record_u32_list_lift_descriptor = host_boundary.record_u32_list_lift_descriptor;
pub const record_byte_list_lift_descriptor = host_boundary.record_byte_list_lift_descriptor;
pub const managed_record_lower_descriptor = "demo:marshal-record-managed-lower/api.write@1.0.0/lower";
pub const managed_record_lower_multi_descriptor = "demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower";
pub const managed_record_lift_descriptor = "demo:marshal-record-managed-lift/api.read@1.0.0/lift";
pub const managed_record_lift_multi_descriptor = "demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift";
pub const nested_record_lift_deeper_descriptor = host_boundary.nested_record_lift_deeper_descriptor;
pub const nested_record_lower_deeper_descriptor = host_boundary.nested_record_lower_deeper_descriptor;
pub const mixed_scalar_list_lower_descriptor = host_boundary.mixed_scalar_list_lower_descriptor;
pub const mixed_text_u32_list_lift_descriptor = host_boundary.mixed_text_u32_list_lift_descriptor;
pub const mixed_text_byte_list_lift_descriptor = host_boundary.mixed_text_byte_list_lift_descriptor;
pub const mixed_text_two_u32_lists_lift_descriptor = host_boundary.mixed_text_two_u32_lists_lift_descriptor;

pub fn emit_module(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    descriptor_id: []const u8,
    entry_tokens: []const lexer.Token,
) ![]u8 {
    if (!host_boundary.is_admitted_descriptor(descriptor_id)) {
        return error.UnsupportedGcWitMarshalDescriptor;
    }
    const is_record_byte_list_lower = std.mem.eql(u8, descriptor_id, record_byte_list_lower_descriptor);
    const is_record_u32_list_lower = std.mem.eql(u8, descriptor_id, record_u32_list_lower_descriptor);
    const is_record_two_u32_lists_lower = std.mem.eql(u8, descriptor_id, record_two_u32_lists_lower_descriptor);
    const is_record_u32_list_lift = std.mem.eql(u8, descriptor_id, record_u32_list_lift_descriptor);
    const is_record_byte_list_lift = std.mem.eql(u8, descriptor_id, record_byte_list_lift_descriptor);
    const is_managed_record_lower_multi = std.mem.eql(u8, descriptor_id, managed_record_lower_multi_descriptor);
    const is_managed_record_lift = std.mem.eql(u8, descriptor_id, managed_record_lift_descriptor);
    const is_managed_record_lift_multi = std.mem.eql(u8, descriptor_id, managed_record_lift_multi_descriptor);
    const is_nested_record_lift_deeper = std.mem.eql(u8, descriptor_id, nested_record_lift_deeper_descriptor);
    const is_nested_record_lower_deeper = std.mem.eql(u8, descriptor_id, nested_record_lower_deeper_descriptor);
    const is_mixed_scalar_list_lower = std.mem.eql(u8, descriptor_id, mixed_scalar_list_lower_descriptor);
    const is_mixed_text_u32_list_lift = std.mem.eql(u8, descriptor_id, mixed_text_u32_list_lift_descriptor);
    const is_mixed_text_byte_list_lift = std.mem.eql(u8, descriptor_id, mixed_text_byte_list_lift_descriptor);
    const is_mixed_text_two_u32_lists_lift = std.mem.eql(u8, descriptor_id, mixed_text_two_u32_lists_lift_descriptor);
    var loaded = try descriptor_loader.load_request_from_manifest(
        io,
        allocator,
        repository_root,
        descriptor_manifest_path,
        descriptor_id,
        null,
    );
    defer loaded.deinit();
    try descriptor_loader.validate_loaded_host_boundary(&loaded, entry_tokens);

    if (is_nested_record_lift_deeper) {
        return nested_lift_deeper_probe.emit_nested_record_lift_deeper_module_from_loaded(allocator, &loaded);
    }
    if (is_nested_record_lower_deeper) {
        return nested_lower_deeper_probe.emit_nested_record_lower_deeper_module_from_loaded(allocator, &loaded);
    }

    const base = try manifest_route.emit_sync_marshal_module_from_loaded_request(
        allocator,
        &loaded,
        null,
        true,
    );
    defer allocator.free(base);

    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
    if (is_managed_record_lift_multi) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $reading (ref null $do_record))
            \\    call $marshal
            \\    local.set $reading
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field0
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    i32.add)
            \\  (export "run" (func $run))
            \\
        );
    } else if (is_managed_record_lift) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $reading (ref null $do_record))
            \\    call $marshal
            \\    local.set $reading
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field0
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    i32.add)
            \\  (export "run" (func $run))
            \\
        );
    } else if (is_record_u32_list_lift) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $reading (ref null $do_record))
            \\    call $marshal
            \\    local.set $reading
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field0
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    i32.const 0
            \\    array.get $do_u32
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    i32.const 1
            \\    array.get $do_u32
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    i32.const 2
            \\    array.get $do_u32
            \\    i32.add
            \\    i32.add)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_mixed_text_u32_list_lift) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $reading (ref null $do_record))
            \\    call $marshal
            \\    local.set $reading
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field0
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 0
            \\    array.get $do_u32
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 1
            \\    array.get $do_u32
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 2
            \\    array.get $do_u32
            \\    i32.add)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_mixed_text_byte_list_lift) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $reading (ref null $do_record))
            \\    call $marshal
            \\    local.set $reading
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field0
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 0
            \\    array.get_s $do_bytes
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 1
            \\    array.get_s $do_bytes
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 2
            \\    array.get_s $do_bytes
            \\    i32.add)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_mixed_text_two_u32_lists_lift) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $reading (ref null $do_record))
            \\    call $marshal
            \\    local.set $reading
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field0
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 0
            \\    array.get $do_u32
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 1
            \\    array.get $do_u32
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field2
            \\    ref.as_non_null
            \\    i32.const 2
            \\    array.get $do_u32
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field3
            \\    ref.as_non_null
            \\    i32.const 0
            \\    array.get $do_u32
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field3
            \\    ref.as_non_null
            \\    i32.const 1
            \\    array.get $do_u32
            \\    i32.add)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_record_byte_list_lift) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $reading (ref null $do_record))
            \\    call $marshal
            \\    local.set $reading
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field0
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    i32.const 0
            \\    array.get_s $do_bytes
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    i32.const 1
            \\    array.get_s $do_bytes
            \\    i32.add
            \\    local.get $reading
            \\    ref.as_non_null
            \\    struct.get $do_record $field1
            \\    ref.as_non_null
            \\    i32.const 2
            \\    array.get_s $do_bytes
            \\    i32.add
            \\    i32.add)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_mixed_scalar_list_lower) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $label (ref null $do_text))
            \\    i32.const 5
            \\    i32.const 104
            \\    i32.const 101
            \\    i32.const 108
            \\    i32.const 108
            \\    i32.const 111
            \\    array.new_fixed $do_bytes 5
            \\    struct.new $do_text
            \\    local.set $label
            \\    i32.const 7
            \\    local.get $label
            \\    i32.const 10
            \\    i32.const 20
            \\    i32.const 5
            \\    array.new_fixed $do_bytes 3
            \\    struct.new $do_record
            \\    call $marshal
            \\    i32.const 42)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_record_byte_list_lower) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    i32.const 7
            \\    i32.const 10
            \\    i32.const 20
            \\    i32.const 5
            \\    array.new_fixed $do_bytes 3
            \\    struct.new $do_record
            \\    call $marshal
            \\    i32.const 42)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_record_u32_list_lower) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    i32.const 7
            \\    i32.const 10
            \\    i32.const 20
            \\    i32.const 30
            \\    array.new_fixed $do_u32 3
            \\    struct.new $do_record
            \\    call $marshal
            \\    i32.const 42)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_record_two_u32_lists_lower) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    i32.const 7
            \\    i32.const 10
            \\    i32.const 20
            \\    i32.const 5
            \\    array.new_fixed $do_u32 3
            \\    i32.const 3
            \\    i32.const 4
            \\    array.new_fixed $do_u32 2
            \\    struct.new $do_record
            \\    call $marshal
            \\    i32.const 34)
            \\  (func $stats (result i32)
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\  (export "stats" (func $stats))
            \\
        );
    } else if (is_managed_record_lower_multi) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $label (ref null $do_text))
            \\    (local $note (ref null $do_text))
            \\    i32.const 5
            \\    i32.const 104
            \\    i32.const 101
            \\    i32.const 108
            \\    i32.const 108
            \\    i32.const 111
            \\    array.new_fixed $do_bytes 5
            \\    struct.new $do_text
            \\    local.set $label
            \\    i32.const 5
            \\    i32.const 119
            \\    i32.const 111
            \\    i32.const 114
            \\    i32.const 108
            \\    i32.const 100
            \\    array.new_fixed $do_bytes 5
            \\    struct.new $do_text
            \\    local.set $note
            \\    i32.const 7
            \\    local.get $label
            \\    local.get $note
            \\    struct.new $do_record
            \\    call $marshal
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\
        );
    } else {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    i32.const 7
            \\    i32.const 5
            \\    i32.const 104
            \\    i32.const 101
            \\    i32.const 108
            \\    i32.const 108
            \\    i32.const 111
            \\    array.new_fixed $do_bytes 5
            \\    struct.new $do_text
            \\    struct.new $do_record
            \\    call $marshal
            \\    global.get $__alloc_count
            \\    i32.const 16
            \\    i32.mul
            \\    global.get $__free_count
            \\    i32.add)
            \\  (export "run" (func $run))
            \\
        );
    }
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

test "GC WIT marshal adapter emits the pinned managed lower module" {
    const source = @embedFile("test/compile_ok/565_gc_wit_managed_record_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(std.testing.io, std.testing.allocator, "..", managed_record_lower_descriptor, tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "GC WIT marshal adapter emits the bounded byte-list lower module" {
    const source = @embedFile("test/compile_ok/592_gc_wit_record_byte_list_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-byte-list-lower/api.write@1.0.0/lower",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-byte-list-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get_s $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "GC WIT marshal adapter emits the mixed scalar-list lower module" {
    const source = @embedFile("test/compile_ok/622_gc_wit_mixed_scalar_list_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        mixed_scalar_list_lower_descriptor,
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"stats\" (func $stats))") != null);
}

test "GC WIT marshal adapter emits the bounded u32-list record lower module" {
    const source = @embedFile("test/compile_ok/601_gc_wit_record_u32_list_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-u32-list-lower/api.write@1.0.0/lower",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-u32-list-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_u32 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "GC WIT marshal adapter emits the bounded two u32-list record lower module" {
    const source = @embedFile("test/compile_ok/657_gc_wit_two_u32_lists_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-two-u32-lists-lower/api@1.0.0") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.new_fixed $do_u32"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 34") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"stats\" (func $stats))") != null);
}

test "C16-C managed record lift emitter emits the managed result module" {
    const source = @embedFile("test/compile_ok/566_gc_wit_managed_record_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-managed-lift/api.read@1.0.0/lift",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "C16-D managed multi-record lift emitter emits the managed result module" {
    const source = @embedFile("test/compile_ok/581_gc_wit_managed_record_lift_multi_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lift-multi/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, wat, "struct.get $do_record $field"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "struct.get $do_text $length"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "GC WIT marshal adapter emits the pinned multi-managed lower module" {
    const source = @embedFile("test/compile_ok/564_gc_wit_managed_record_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        managed_record_lower_multi_descriptor,
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lower-multi/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32)))") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.new_fixed $do_bytes 5"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $label (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $note (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "GC WIT marshal adapter rejects an unknown descriptor before emission" {
    try std.testing.expectError(
        error.UnsupportedGcWitMarshalDescriptor,
        emit_module(
            std.testing.io,
            std.testing.allocator,
            "..",
            "demo:unknown/api.write@1.0.0/lower",
            &.{},
        ),
    );
}

test "C14 four-level nested scalar lift compiler route emits a module" {
    const source = @embedFile("test/compile_ok/586_gc_wit_nested_record_deeper_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lift-deeper/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "C14 four-level nested scalar lower compiler route emits a module" {
    const source = @embedFile("test/compile_ok/587_gc_wit_nested_record_deeper_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lower-deeper/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i64 i64 i64 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "GC WIT marshal C16-A rejects a generic entry without the host declaration" {
    const source = @embedFile("test/compile_ok/01_start_entry_valid.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(
        error.MissingGcWitHostDeclaration,
        emit_module(
            std.testing.io,
            std.testing.allocator,
            "..",
            managed_record_lower_multi_descriptor,
            tokens,
        ),
    );
}

test "C18 record u32 list lift compiler route emits a module" {
    const source =
        \\Reading {
        \\    code u32
        \\    payload [u32]
        \\}
        \\read = @host_func("demo:marshal-record-u32-list-lift/api@1.0.0", "read", () -> Reading)
        \\
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        "demo:marshal-record-u32-list-lift/api.read@1.0.0/lift",
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-u32-list-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "G5c mixed text u32-list lift compiler route emits a module" {
    const source = @embedFile("test/compile_ok/639_gc_wit_mixed_text_u32_list_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        mixed_text_u32_list_lift_descriptor,
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_u32 3") == null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"stats\" (func $stats))") != null);
}

test "G5c mixed text byte-list lift compiler route emits a module" {
    const source = @embedFile("test/compile_ok/648_gc_wit_mixed_text_byte_list_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        mixed_text_byte_list_lift_descriptor,
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 4") == null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"stats\" (func $stats))") != null);
}

test "G5c mixed text and two u32-list lift compiler route emits measured module" {
    const source = @embedFile("test/compile_ok/673_gc_wit_mixed_text_two_u32_lists_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const descriptor = "demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift";
    const wat = try emit_module(
        std.testing.io,
        std.testing.allocator,
        "..",
        descriptor,
        tokens,
    );
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_bytes") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.new_default $do_u32"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "(global $__marshal_heap (mut i32) (i32.const 28))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"stats\" (func $stats))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed") == null);
}
