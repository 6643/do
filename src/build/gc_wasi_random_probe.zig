//! A single bounded WASI registry-backed GC list<u8> lift probe.
//!
//! This is an admission gate, not the default compiler route. It proves that
//! the checked-in WASI source, fixed registry signature, canonical import, and
//! GC-to-linear-memory lift agree for one synchronous operation.
const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");
const wasi_registry = @import("codegen_wasi_registry.zig");

const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
const descriptor_id = "wasi:random/random.get-random-bytes@0.3.0-rc-2025-09-16/lift";

fn random_bytes_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .byte_list = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 1,
        .element_stride = 1,
        .element_alignment = 1,
        .capacity = 16,
        .accepted_lengths = &.{ 0, 1, 16 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } };
}

pub fn emit_random_bytes_lift_module(
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
        random_bytes_measurement(),
        16,
    );
    defer allocator.free(base);

    // The manifest-backed module is extended below with a probe export.
    if (!std.mem.endsWith(u8, base, ")\n")) return error.InvalidGeneratedModule;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - 2]);
    try out.appendSlice(allocator, "  (func $run (result i32)\n" ++
        "    (local $bytes (ref null $do_bytes))\n" ++
        "    call $marshal\n" ++
        "    local.set $bytes\n" ++
        "    local.get $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    array.len)\n" ++
        "  (export \"run\" (func $run))\n)\n");
    return out.toOwnedSlice(allocator);
}

test "WASI registry admits random bytes as a bounded GC lift" {
    const signature = wasi_registry.known_wasi_wit_signature("random/random/get-random-bytes") orelse
        return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("u64", signature.params);
    try std.testing.expectEqualStrings("list<u8>", signature.result);

    const wat = try emit_random_bytes_lift_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"wasi:random/random@0.3.0-rc-2025-09-16\" \"get-random-bytes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i64 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"wasi:random/random@0.3.0-rc-2025-09-16\" \"get-random-bytes\" (func $canonical_call (type $canonical_lift)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"wasi:random/random@0.3.0-rc-2025-09-16\" \"get-random-bytes\" (func $canonical_call (param (ref") == null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcWasiRandomProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_random_bytes_lift_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
