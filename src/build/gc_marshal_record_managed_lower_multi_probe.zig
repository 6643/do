//! Private manifest-backed `{u32, string, string}` record lower probe.
//!
//! The descriptor, source hash, and measured record layout are checked before
//! this module is emitted. The generated Core module is used only by the
//! bounded Component host/equivalence gates; the default host/WIT route stays
//! on its existing path.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");

const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
const descriptor_id = "demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower";

fn managed_record_lower_multi_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 20,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
            .{ .name = "note", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
    } };
}

pub fn emit_managed_record_lower_multi_module(
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
        managed_record_lower_multi_measurement(),
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
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

test "multi-managed-text record lower probe emits the five-word host entry" {
    const wat = try emit_managed_record_lower_multi_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lower-multi/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32)))") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalManagedRecordLowerMultiProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_managed_record_lower_multi_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
