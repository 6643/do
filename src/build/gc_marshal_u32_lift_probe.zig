//! A private manifest-backed GC list<u32> lift probe.
//!
//! The descriptor, source hash, and measured list layout are checked before
//! this module is emitted. The resulting Core module is intended for the
//! existing Component host/equivalence gates, not for the default compiler
//! host/WIT route.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");

const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
const descriptor_id = "demo:marshal-u32-lift-host/api.receive@1.0.0/lift";

fn u32_list_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .list = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 4,
        .element_stride = 4,
        .element_alignment = 4,
        .ticket_offset = 0,
        .capacity = 3,
        .accepted_lengths = &.{ 0, 1, 2, 3 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } }, .children = &.{.{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } }} };
}

pub fn emit_u32_list_lift_module(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
) ![]u8 {
    const base = try manifest_route.emit_sync_marshal_module_from_manifest(
        io,
        allocator,
        repository_root,
        descriptor_manifest_path,
        descriptor_id,
        u32_list_measurement(),
        null,
    );
    defer allocator.free(base);

    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
    try generated_text.append_block(allocator, &out, 0,
                \\  (func $run (result i32)
        \\    (local $values (ref null $do_u32))
        \\    call $marshal
        \\    local.set $values
        \\    local.get $values
        \\    ref.as_non_null
        \\    i32.const 0
        \\    array.get $do_u32
        \\    local.get $values
        \\    ref.as_non_null
        \\    i32.const 1
        \\    array.get $do_u32
        \\    i32.add
        \\    local.get $values
        \\    ref.as_non_null
        \\    i32.const 2
        \\    array.get $do_u32
        \\    i32.add)
        \\  (export "run" (func $run))
        \\)
        \\
        );
    return out.toOwnedSlice(allocator);
}

test "manifest-backed u32 list lift probe emits a lift entry" {
    const wat = try emit_u32_list_lift_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $run (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_u32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalU32LiftProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_u32_list_lift_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
