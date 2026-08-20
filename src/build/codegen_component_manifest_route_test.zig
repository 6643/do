const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");

const manifest_path = "doc/wit/gc_descriptor_manifest.json";
const random_descriptor = "wasi:random/random.get-random-bytes@0.3.0-rc-2025-09-16/lift";
const text_descriptor = "demo:marshal-equivalence/api.send@1.0.0/lower";

fn random_measurement() marshal.MeasuredNode {
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

test "manifest route emits the pinned random GC lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        random_descriptor,
        random_measurement(),
        16,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "wasi:random/random@0.3.0-rc-2025-09-16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i64 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"wasi:random/random@0.3.0-rc-2025-09-16\" \"get-random-bytes\" (func $canonical_call (param (ref") == null);
}

test "manifest route rejects an unknown descriptor before emission" {
    try std.testing.expectError(error.DescriptorNotFound, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        "wasi:random/random.missing@0.3.0-rc-2025-09-16/lift",
        random_measurement(),
        16,
    ));
}

test "manifest route emits the pinned text lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        text_descriptor,
        text_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-equivalence/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-equivalence/api@1.0.0\" \"send\"") != null);
}
