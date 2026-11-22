const std = @import("std");
const generated_text = @import("codegen_text.zig");
const route = @import("codegen_component_marshal_route.zig");
const marshal = @import("codegen_component_marshal_plan.zig");

fn option_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .variant = .{
        .tag_offset = 0,
        .payload_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .cases = &.{
            .{ .name = "none", .tag = 0, .payload_required = false, .payload = null },
            .{ .name = "some", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
        },
    } }, .children = &.{.{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } }} };
}

fn result_measurement(indirect: bool) marshal.MeasuredNode {
    return .{ .layout = .{ .variant = .{
        .tag_offset = 0,
        .payload_offset = 4,
        .byte_size = 12,
        .alignment = 4,
        .indirect = if (indirect) .{ .core_words = &.{ .i32 }, .allocation = .cabi_realloc, .free = .cabi_realloc } else null,
        .cases = &.{
            .{ .name = "ok", .tag = 0, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 8, .alignment = 4, .core_type = .i32 } },
            .{ .name = "err", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
        },
    } }, .children = &.{
        .{ .layout = .{ .text = .{ .pointer_offset = 0, .length_offset = 4, .byte_size = 8, .alignment = 4, .allocation = .cabi_realloc, .free = .cabi_realloc } } },
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    } };
}

fn variant_measurement(drift: bool) marshal.MeasuredNode {
    return .{ .layout = .{ .variant = .{
        .tag_offset = 0,
        .payload_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .cases = &.{
            .{ .name = if (drift) "different" else "none", .tag = 0, .payload_required = false, .payload = null },
            .{ .name = "value", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
        },
    } }, .children = &.{.{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } }} };
}

fn unsupported_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } };
}

fn append_run(allocator: std.mem.Allocator, wat: []const u8, mode: []const u8) ![]u8 {
    if (!std.mem.endsWith(u8, wat, ")\n")) return error.InvalidGeneratedModule;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, wat[0 .. wat.len - 2]);
    if (std.mem.eql(u8, mode, "option")) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $payload (ref null $do_variant_i32))
            \\    i32.const 7
            \\    struct.new $do_variant_i32
            \\    local.set $payload
            \\    i32.const 1
            \\    local.get $payload
            \\    struct.new $do_variant
            \\    call $marshal
            \\    i32.const 1)
            \\  (export "run" (func $run))
        );
    } else if (std.mem.eql(u8, mode, "result-text-lower")) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $text (ref null $do_text))
            \\    i32.const 5
            \\    i32.const 104
            \\    i32.const 101
            \\    i32.const 108
            \\    i32.const 108
            \\    i32.const 111
            \\    array.new_fixed $do_u8 5
            \\    struct.new $do_text
            \\    local.set $text
            \\    i32.const 0
            \\    local.get $text
            \\    struct.new $do_variant
            \\    call $marshal
            \\    i32.const 1)
            \\  (export "run" (func $run))
            \\  (func $allocs (result i32) global.get $__alloc_count)
            \\  (func $frees (result i32) global.get $__free_count)
            \\  (export "allocs" (func $allocs))
            \\  (export "frees" (func $frees))
        );
    } else if (std.mem.eql(u8, mode, "result-scalar-lower")) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $payload (ref null $do_variant_i32))
            \\    i32.const 7
            \\    struct.new $do_variant_i32
            \\    local.set $payload
            \\    i32.const 1
            \\    local.get $payload
            \\    struct.new $do_variant
            \\    call $marshal
            \\    i32.const 2)
            \\  (export "run" (func $run))
            \\  (func $allocs (result i32) global.get $__alloc_count)
            \\  (func $frees (result i32) global.get $__free_count)
            \\  (export "allocs" (func $allocs))
            \\  (export "frees" (func $frees))
        );
    } else if (std.mem.eql(u8, mode, "result-text-lift") or std.mem.eql(u8, mode, "result-scalar-lift")) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    (local $value (ref null $do_variant))
            \\    call $marshal
            \\    local.set $value
            \\    local.get $value
            \\    ref.as_non_null
            \\    struct.get $do_variant $tag)
            \\  (export "run" (func $run))
            \\  (func $allocs (result i32) global.get $__alloc_count)
            \\  (func $frees (result i32) global.get $__free_count)
            \\  (export "allocs" (func $allocs))
            \\  (export "frees" (func $frees))
        );
    } else if (std.mem.eql(u8, mode, "variant-none")) {
        try generated_text.append_block(allocator, &out, 2,
            \\  (func $run (result i32)
            \\    i32.const 0
            \\    ref.null any
            \\    struct.new $do_variant
            \\    call $marshal
            \\    i32.const 1)
            \\  (export "run" (func $run))
        );
    }
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 6) return error.InvalidArgs;
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.gpa, .limited(1024 * 1024));
    defer init.gpa.free(source);
    const direction: marshal.Direction = if (std.mem.eql(u8, args[3], "lower")) .lower else .lift;
    const measured = if (std.mem.eql(u8, args[4], "option")) option_measurement()
        else if (std.mem.startsWith(u8, args[4], "result-")) result_measurement(direction == .lift)
        else if (std.mem.eql(u8, args[4], "drift")) variant_measurement(true)
        else if (std.mem.eql(u8, args[4], "unsupported")) unsupported_measurement()
        else variant_measurement(false);
    const base = try route.emit_sync_marshal_module_from_wit_source(init.gpa, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = args[2],
        .direction = direction,
        .measured = measured,
        .emit_realloc_counters = true,
    });
    defer init.gpa.free(base);
    const wat = try append_run(init.gpa, base, args[4]);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[5], .data = wat });
}
