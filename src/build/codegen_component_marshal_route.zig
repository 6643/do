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

    return emit_sync_marshal_module_from_plan(allocator, &plan, request.canonical_u64_arg);
}

/// Emit a module from a parser-backed, measured plan. The plan owns the
/// descriptor identity used to derive and validate the canonical Component
/// import; no independent package/member/source facts are accepted here.
pub fn emit_sync_marshal_module_from_plan(
    allocator: std.mem.Allocator,
    plan: *const marshal.SyncValuePlan,
    canonical_u64_arg: ?u64,
) ![]u8 {
    const canonical_import = try marshal_module.canonical_import_for_plan(allocator, plan.descriptor);
    defer allocator.free(canonical_import.module);

    return marshal_module.emit_sync_marshal_module(allocator, plan, .{
        .direction = plan.direction,
        .canonical_import_module = canonical_import.module,
        .canonical_import_name = canonical_import.name,
        .canonical_u64_arg = canonical_u64_arg,
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
