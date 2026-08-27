//! Private manifest-backed mixed text/byte-list record lift probe.
//!
//! The descriptor, source hash, and measured record layout are checked before
//! this module is emitted. The generated Core module is used by the bounded
//! Component host/equivalence gates; it does not widen the default WIT shape.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");

const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
const descriptor_id = "demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift";

fn mixed_text_byte_list_lift_measurement() marshal.MeasuredNode {
    return .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "payload", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .byte_list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 1,
                .element_stride = 1,
                .element_alignment = 1,
                .capacity = 4,
                .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    };
}

pub fn emit_mixed_text_byte_list_lift_module(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
) ![]u8 {
    const base = try manifest_route.emit_sync_marshal_module_from_manifest_with_options(
        io,
        allocator,
        repository_root,
        descriptor_manifest_path,
        descriptor_id,
        mixed_text_byte_list_lift_measurement(),
        null,
        true,
    );
    defer allocator.free(base);

    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
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
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

test "mixed text byte-list lift probe emits the fixed host entry" {
    const wat = try emit_mixed_text_byte_list_lift_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get_s $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"stats\" (func $stats))") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "call $cabi_realloc"));
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalRecordMixedTextByteListLiftProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_mixed_text_byte_list_lift_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
