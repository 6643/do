//! Private manifest-backed four-level nested scalar-record lift probe.
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
const descriptor_id = "demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift";

fn nested_record_measurement() marshal.MeasuredNode {
    return @import("gc_marshal_record_nested_lower_deeper_probe.zig").nested_record_measurement();
}

pub fn emit_nested_record_lift_deeper_module(
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
    return emit_nested_record_lift_deeper_module_from_loaded(allocator, &loaded);
}

pub fn emit_nested_record_lift_deeper_module_from_loaded(
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
        \\    (local $reading (ref null $do_record))
        \\    (local $detail (ref null $do_detail))
        \\    (local $header (ref null $do_header))
        \\    (local $leaf (ref null $do_leaf))
        \\    call $marshal
        \\    local.set $reading
        \\    local.get $reading
        \\    ref.as_non_null
        \\    struct.get $do_record $field0
        \\    local.set $detail
        \\    local.get $detail
        \\    ref.as_non_null
        \\    struct.get $do_detail $field0
        \\    local.set $header
        \\    local.get $header
        \\    ref.as_non_null
        \\    struct.get $do_header $field0
        \\    local.set $leaf
        \\    local.get $leaf
        \\    ref.as_non_null
        \\    struct.get $do_leaf $field0
        \\    local.get $leaf
        \\    ref.as_non_null
        \\    struct.get $do_leaf $field1
        \\    i32.wrap_i64
        \\    i32.add
        \\    local.get $header
        \\    ref.as_non_null
        \\    struct.get $do_header $field1
        \\    i32.wrap_i64
        \\    i32.add
        \\    local.get $detail
        \\    ref.as_non_null
        \\    struct.get $do_detail $field1
        \\    i32.wrap_i64
        \\    i32.add
        \\    local.get $reading
        \\    ref.as_non_null
        \\    struct.get $do_record $field1
        \\    i32.wrap_i64
        \\    i32.add)
        \\  (export "run" (func $run))
    );
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

test "manifest-backed four-level nested scalar record lift probe emits a host entry" {
    const wat = try emit_nested_record_lift_deeper_module(std.testing.io, std.testing.allocator, "..");
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lift-deeper/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 8\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 16\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 24\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 32\n    i32.add\n    i64.load") != null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2 and args.len != 3) return error.InvalidGcMarshalRecordNestedLiftDeeperProbeArgs;
    const repository_root = if (args.len == 3) args[2] else ".";
    const wat = try emit_nested_record_lift_deeper_module(init.io, init.gpa, repository_root);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = wat });
}
