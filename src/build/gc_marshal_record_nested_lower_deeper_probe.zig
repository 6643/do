//! Private manifest-backed four-level nested scalar-record lower probe.
//!
//! The descriptor, source hash, and measured four-level record layout are
//! checked before this module is emitted. The generated Core module is used
//! only by the bounded Component host/equivalence gates; the default host/WIT
//! route stays on its existing path.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const descriptor_loader = @import("codegen_component_descriptor_manifest.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");

const descriptor_manifest_path = "doc/wit/gc_descriptor_manifest.json";
const descriptor_id = "demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower";

pub fn nested_record_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 40,
        .alignment = 8,
        .fields = &.{
            .{ .name = "detail", .offset = 0, .byte_size = 32, .alignment = 8, .indirect = null },
            .{ .name = "tail", .offset = 32, .byte_size = 8, .alignment = 8, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .record = .{
            .byte_size = 32,
            .alignment = 8,
            .fields = &.{
                .{ .name = "header", .offset = 0, .byte_size = 24, .alignment = 8, .indirect = null },
                .{ .name = "marker", .offset = 24, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } }, .children = &.{
            .{ .layout = .{ .record = .{
                .byte_size = 24,
                .alignment = 8,
                .fields = &.{
                    .{ .name = "leaf", .offset = 0, .byte_size = 16, .alignment = 8, .indirect = null },
                    .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
                },
            } }, .children = &.{
                .{ .layout = .{ .record = .{
                    .byte_size = 16,
                    .alignment = 8,
                    .fields = &.{
                        .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                        .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
                    },
                } }, .children = &.{
                    .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                    .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
                } },
                .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            } },
            .{ .layout = .{ .scalar = .{ .offset = 24, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        } },
        .{ .layout = .{ .scalar = .{ .offset = 32, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
    } };
}

pub fn emit_nested_record_lower_deeper_module(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
) ![]u8 {
    var loaded = try descriptor_loader.load_request_from_manifest(
        io,
        allocator,
        repository_root,
        descriptor_manifest_path,
        descriptor_id,
        null,
    );
    defer loaded.deinit();
    return emit_nested_record_lower_deeper_module_from_loaded(allocator, &loaded);
}

pub fn emit_nested_record_lower_deeper_module_from_loaded(
    allocator: std.mem.Allocator,
    loaded: *const descriptor_loader.LoadedRequest,
) ![]u8 {
    const base = try manifest_route.emit_sync_marshal_module_from_loaded_request(
        allocator,
        loaded,
        null,
        false,
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
        \\    (local $detail (ref null $do_detail))
        \\    (local $header (ref null $do_header))
        \\    (local $leaf (ref null $do_leaf))
        \\    i32.const 7
        \\    i64.const 35
        \\    struct.new $do_leaf
        \\    local.set $leaf
        \\    local.get $leaf
        \\    i64.const -5
        \\    struct.new $do_header
        \\    local.set $header
        \\    local.get $header
        \\    i64.const 11
        \\    struct.new $do_detail
        \\    local.set $detail
        \\    local.get $detail
        \\    i64.const -6
        \\    struct.new $do_record
        \\    local.set $writing
        \\    local.get $writing
        \\    call $marshal
        \\    i32.const 42)
        \\  (export "run" (func $run))
    );
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

test "manifest-backed four-level nested scalar record lower probe emits a host entry" {
    const wat = try emit_nested_record_lower_deeper_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lower-deeper/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i64 i64 i64 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_leaf $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_header $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_detail $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-nested-lower-deeper/api@1.0.0\" \"write\" (func $canonical_call (param (ref)") == null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalRecordNestedLowerDeeperProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_nested_record_lower_deeper_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
