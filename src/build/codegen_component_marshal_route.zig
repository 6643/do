const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const marshal_module = @import("codegen_component_marshal_module.zig");
const marshal_registry = @import("codegen_component_marshal_registry.zig");

pub const Request = struct {
    source: []const u8,
    world_name: []const u8,
    interface_name: []const u8,
    member_name: []const u8,
    direction: marshal.Direction,
    measured: marshal.MeasuredNode,
    canonical_u64_arg: ?u64 = null,
    emit_realloc_counters: bool = false,
};

pub fn emit_sync_marshal_module_from_wit_source(
    allocator: std.mem.Allocator,
    request: Request,
) ![]u8 {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        allocator,
        request.source,
        request.world_name,
        request.interface_name,
        request.member_name,
        request.direction,
        request.measured,
    );
    defer marshal.deinit_sync_value_plan(allocator, plan);

    return emit_sync_marshal_module_from_plan(
        allocator,
        &plan,
        request.canonical_u64_arg,
        request.emit_realloc_counters,
    );
}

/// Emit a module from a parser-backed, measured plan. The plan owns the
/// descriptor identity used to derive and validate the canonical Component
/// import; no independent package/member/source facts are accepted here.
pub fn emit_sync_marshal_module_from_plan(
    allocator: std.mem.Allocator,
    plan: *const marshal.SyncValuePlan,
    canonical_u64_arg: ?u64,
    emit_realloc_counters: bool,
) ![]u8 {
    const canonical_import = try marshal_module.canonical_import_for_plan(allocator, plan.descriptor);
    defer allocator.free(canonical_import.module);

    return marshal_module.emit_sync_marshal_module(allocator, plan, .{
        .direction = plan.direction,
        .canonical_import_module = canonical_import.module,
        .canonical_import_name = canonical_import.name,
        .canonical_u64_arg = canonical_u64_arg,
        .emit_realloc_counters = emit_realloc_counters,
    });
}

const source_wit =
    \\package demo:marshal-route@1.0.0;
    \\
    \\interface api {
    \\  read: func() -> u32;
    \\}
    \\
    \\world probe { import api; }
;

const map_source_wit =
    \\package demo:marshal-route-map@1.0.0;
    \\
    \\interface api {
    \\  lookup: func(value: map<u32, u32>) -> map<u32, u32>;
    \\}
    \\
    \\world probe { import api; }
;

test "component marshal route resolves a parser-backed member" {
    const wat = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source_wit,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "read",
        .direction = .lift,
        .measured = .{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .core_type = .i32,
        } } },
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-route/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result i32)") != null);
}

test "component marshal route resolves a parser-backed map member" {
    const measured = marshal.MeasuredNode{
        .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 8,
            .element_stride = 8,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 4, .alignment = 4 },
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    };

    const lower = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = map_source_wit,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "lookup",
        .direction = .lower,
        .measured = measured,
    });
    defer std.testing.allocator.free(lower);
    try std.testing.expect(std.mem.indexOf(u8, lower, "demo:marshal-route-map/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(param $input (ref null $do_map))") != null);

    const lift = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = map_source_wit,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "lookup",
        .direction = .lift,
        .measured = measured,
    });
    defer std.testing.allocator.free(lift);
    try std.testing.expect(std.mem.indexOf(u8, lift, "demo:marshal-route-map/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(result (ref null $do_map))") != null);
}
