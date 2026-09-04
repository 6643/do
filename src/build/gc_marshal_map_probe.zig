//! Standalone Core-Wasm validation probe for the bounded map routes.
//!
//! The probe intentionally stops at Core WAT parse/validate. The map shape is
//! not yet admitted by the component/WIT registry, so this is a lowering gate,
//! not a claim of general map or Component support.
const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const marshal_module = @import("codegen_component_marshal_module.zig");
const wit = @import("wit_abi_types.zig");

const ProbeMapValue = enum { u32, text };

fn map_measurement(value_kind: ProbeMapValue) marshal.MeasuredNode {
    if (value_kind == .text) {
        return .{ .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 12,
            .element_stride = 12,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 8, .alignment = 4 },
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
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
    return .{ .layout = .{ .map = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 8,
        .element_stride = 8,
        .element_alignment = 4,
        .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
        .value = .{ .offset = 4, .byte_size = 4, .alignment = 4 },
        .capacity = 4,
        .accepted_lengths = &.{ 0, 1, 4 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    } };
}

pub fn emit_map_module(
    allocator: std.mem.Allocator,
    direction: marshal.Direction,
) ![]u8 {
    return emit_map_module_for_value(allocator, direction, .u32);
}

pub fn emit_map_text_module(
    allocator: std.mem.Allocator,
    direction: marshal.Direction,
) ![]u8 {
    return emit_map_module_for_value(allocator, direction, .text);
}

fn emit_map_module_for_value(
    allocator: std.mem.Allocator,
    direction: marshal.Direction,
    value_kind: ProbeMapValue,
) ![]u8 {
    var key = wit.AbiType.scalar(allocator, .u32);
    defer key.deinit();
    var value = switch (value_kind) {
        .u32 => wit.AbiType.scalar(allocator, .u32),
        .text => wit.AbiType.text(allocator),
    };
    defer value.deinit();
    var map = try wit.AbiType.map(allocator, &key, &value);
    defer map.deinit();

    const descriptor = marshal.DescriptorIdentity{
        .package = if (value_kind == .text) "demo:marshal-map-text@1.0.0" else "demo:marshal-map@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = if (direction == .lower)
            "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        else
            "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    };
    const plan = try marshal.build_sync_value_plan_with_layout(
        allocator,
        descriptor,
        &map,
        direction,
        map_measurement(value_kind),
    );
    defer marshal.deinit_sync_value_plan(allocator, plan);

    return marshal_module.emit_sync_marshal_module(allocator, &plan, .{
        .direction = direction,
        .canonical_import_module = if (value_kind == .text) "demo:marshal-map-text/api@1.0.0" else "demo:marshal-map/api@1.0.0",
        .canonical_import_name = "lookup",
    });
}

test "map probe emits both bounded directions" {
    const lower = try emit_map_module(std.testing.allocator, .lower);
    defer std.testing.allocator.free(lower);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(type $do_map") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(type $canonical_lower (func (param i32 i32)))") != null);

    const lift = try emit_map_module(std.testing.allocator, .lift);
    defer std.testing.allocator.free(lift);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(type $do_map") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(type $canonical_lift (func (param i32)))") != null);

    const text_lower = try emit_map_text_module(std.testing.allocator, .lower);
    defer std.testing.allocator.free(text_lower);
    try std.testing.expect(std.mem.indexOf(u8, text_lower, "(type $do_text_array") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_lower, "array.get $do_text_array") != null);

    const text_lift = try emit_map_text_module(std.testing.allocator, .lift);
    defer std.testing.allocator.free(text_lift);
    try std.testing.expect(std.mem.indexOf(u8, text_lift, "(type $do_text_array") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_lift, "array.set $do_text_array") != null);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3 and args.len != 4) return error.InvalidGcMarshalMapProbeArgs;
    const direction: marshal.Direction = if (std.mem.eql(u8, args[1], "lower"))
        .lower
    else if (std.mem.eql(u8, args[1], "lift"))
        .lift
    else
        return error.InvalidGcMarshalMapProbeDirection;
    var value_kind: ProbeMapValue = .u32;
    var output_index: usize = 2;
    if (args.len == 4) {
        value_kind = if (std.mem.eql(u8, args[2], "text"))
            .text
        else if (std.mem.eql(u8, args[2], "u32"))
            .u32
        else
            return error.InvalidGcMarshalMapProbeValue;
        output_index = 3;
    }
    const wat = try emit_map_module_for_value(init.gpa, direction, value_kind);
    defer init.gpa.free(wat);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[output_index], .data = wat });
}
