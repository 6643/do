//! Private manifest-backed scalar-plus-text record lift probe.
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
const descriptor_id = "demo:marshal-record-managed-lift/api.read@1.0.0/lift";

fn managed_record_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 12,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
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
    } };
}

pub fn emit_managed_record_lift_module(
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
        managed_record_measurement(),
        null,
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
        \\    i32.add)
        \\  (export "run" (func $run))
    );
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

test "manifest-backed managed-field record lift probe emits a host entry" {
    const wat = try emit_managed_record_lift_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $field1 (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_text $length") != null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalManagedRecordLiftProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_managed_record_lift_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
