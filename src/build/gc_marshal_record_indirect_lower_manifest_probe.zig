//! Private manifest-backed indirect scalar-record lower probe.
//!
//! The descriptor, source hash, and measured 17-field record layout are
//! checked before this module is emitted. The generated Core module is used
//! only by the bounded Component host/equivalence gates; the default host/WIT
//! route stays on its existing path.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");
const wit_layout = @import("wit_abi_layout.zig");

const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
const descriptor_id = "demo:marshal-record-indirect-lower/api.write@1.0.0/lower";

fn make_record_fields() [17]wit_layout.FieldMeasurement {
    var fields: [17]wit_layout.FieldMeasurement = undefined;
    inline for (0..17) |index| {
        fields[index] = .{
            .name = comptime std.fmt.comptimePrint("f{d}", .{index}),
            .offset = @intCast(index * 8),
            .byte_size = 8,
            .alignment = 8,
            .indirect = null,
        };
    }
    return fields;
}

fn make_record_children() [17]marshal.MeasuredNode {
    var children: [17]marshal.MeasuredNode = undefined;
    inline for (0..17) |index| {
        children[index] = .{ .layout = .{ .scalar = .{
            .offset = @intCast(index * 8),
            .byte_size = 8,
            .alignment = 8,
            .core_type = .i64,
        } } };
    }
    return children;
}

const record_fields = make_record_fields();
const record_children = make_record_children();

fn indirect_record_measurement() marshal.MeasuredNode {
    return .{
        .layout = .{ .record = .{
            .byte_size = 136,
            .alignment = 8,
            .fields = &record_fields,
            .indirect = .{
                .core_words = &.{.i32},
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            },
        } },
        .children = &record_children,
    };
}

pub fn emit_indirect_record_lower_module(
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
        indirect_record_measurement(),
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
        \\    (local $writing (ref null $do_record))
        \\
        );
    inline for (0..17) |index| {
        try generated_text.append_fmt(allocator, &out, "    i64.const {[value]d}\n", .{ .value = index + 1 });
    }
    try generated_text.append_block(allocator, &out, 2,
                \\    struct.new $do_record
        \\    local.set $writing
        \\    local.get $writing
        \\    call $marshal
        \\    i32.const 42)
        \\  (export "run" (func $run))
        \\
        );
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

test "manifest-backed indirect scalar record lower probe emits a host entry" {
    const wat = try emit_indirect_record_lower_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-indirect-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store offset=128") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalRecordIndirectLowerManifestProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_indirect_record_lower_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
