//! A private manifest-backed GC text lower probe.
//!
//! The descriptor, source hash, and measured text layout are checked before
//! this module is emitted. The resulting Core module is intended for the
//! existing ARC/GC Component equivalence gate, not for the default compiler
//! host/WIT route.
const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");

const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
const descriptor_id = "demo:marshal-equivalence/api.send@1.0.0/lower";

fn text_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .text = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } };
}

pub fn emit_text_lower_module(
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
        text_measurement(),
        null,
        true,
    );
    defer allocator.free(base);

    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
    try out.appendSlice(allocator,
        "  (func $run (result i32)\n" ++
            "    i32.const 5\n" ++
            "    i32.const 104\n" ++
            "    i32.const 101\n" ++
            "    i32.const 108\n" ++
            "    i32.const 108\n" ++
            "    i32.const 111\n" ++
            "    array.new_fixed $do_bytes 5\n" ++
            "    struct.new $do_text\n" ++
            "    call $marshal\n" ++
            "    global.get $__alloc_count\n" ++
            "    i32.const 16\n" ++
            "    i32.mul\n" ++
            "    global.get $__free_count\n" ++
            "    i32.add)\n" ++
            "  (export \"run\" (func $run))\n)\n");
    return out.toOwnedSlice(allocator);
}

test "manifest-backed text probe emits a lower entry" {
    const wat = try emit_text_lower_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $run (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(global $__alloc_count (mut i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(global $__free_count (mut i32)") != null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalTextProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_text_lower_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
