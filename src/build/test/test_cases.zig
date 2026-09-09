pub const Kind = enum {
    compiler_smoke,
    wit_map,
    component_assembly,
    assembly_validation,
    wit_snapshot_validation,
    p3_pure_lowering_matrix,
    rust_async_runner,
    compiler_fixture_matrix,
    compiler_compiled_fixture_matrix,
    compiler_auxiliary_matrix,
    compiler_compiled_trap_matrix,
    wasm_smoke_matrix,
    gc_default_matrix,
    component_template_validation,
    tool_matrix,
    external_dependency_negative_matrix,
    socket_abi_matrix,
    structural_gate,
    gc_core_oracle,
    gc_runtime_oracle,
    gc_assembly_matrix,
    map_core_probe,
    map_sync_component,
    map_async_component,
    gc_arc_inventory,
    gc_backend_firewall,
    gc_component_boundary,
};

pub const Case = struct {
    name: []const u8,
    kind: Kind,
};

pub const cases = [_]Case{
    .{ .name = "compiler smoke", .kind = .compiler_smoke },
    .{ .name = "wit map parser", .kind = .wit_map },
    .{ .name = "component assembly", .kind = .component_assembly },
    .{ .name = "assembly validation", .kind = .assembly_validation },
    .{ .name = "WIT snapshot validation", .kind = .wit_snapshot_validation },
    .{ .name = "P3 pure lowering matrix", .kind = .p3_pure_lowering_matrix },
    .{ .name = "rust async runner", .kind = .rust_async_runner },
    .{ .name = "compiler fixture matrix", .kind = .compiler_fixture_matrix },
    .{ .name = "compiled fixture matrix", .kind = .compiler_compiled_fixture_matrix },
    .{ .name = "compiler auxiliary matrix", .kind = .compiler_auxiliary_matrix },
    .{ .name = "compiler compiled trap matrix", .kind = .compiler_compiled_trap_matrix },
    .{ .name = "WASM smoke matrix", .kind = .wasm_smoke_matrix },
    .{ .name = "GC default matrix", .kind = .gc_default_matrix },
    .{ .name = "component metadata templates", .kind = .component_template_validation },
    .{ .name = "CLI and tool matrix", .kind = .tool_matrix },
    .{ .name = "external dependency negative matrix", .kind = .external_dependency_negative_matrix },
    .{ .name = "socket ABI matrix", .kind = .socket_abi_matrix },
    .{ .name = "structural gate bridge", .kind = .structural_gate },
    .{ .name = "Core GC oracle bridge", .kind = .gc_core_oracle },
    .{ .name = "GC runtime oracle matrix", .kind = .gc_runtime_oracle },
    .{ .name = "GC assembly matrix", .kind = .gc_assembly_matrix },
    .{ .name = "bounded map Core ABI probe", .kind = .map_core_probe },
    .{ .name = "manifest-backed map Component host gate", .kind = .map_sync_component },
    .{ .name = "async map Component capability gate", .kind = .map_async_component },
    .{ .name = "GC ARC inventory classification", .kind = .gc_arc_inventory },
    .{ .name = "GC backend firewall", .kind = .gc_backend_firewall },
    .{ .name = "GC Component boundary and resource cleanup", .kind = .gc_component_boundary },
};

test "integration case table is stable and non-empty" {
    const std = @import("std");
    try std.testing.expect(cases.len >= 25);
    try std.testing.expectEqual(Kind.compiler_smoke, cases[0].kind);
    try std.testing.expectEqual(Kind.wit_map, cases[1].kind);
    try std.testing.expectEqual(Kind.component_assembly, cases[2].kind);
    try std.testing.expectEqual(Kind.assembly_validation, cases[3].kind);
    try std.testing.expectEqual(Kind.wit_snapshot_validation, cases[4].kind);
    try std.testing.expectEqual(Kind.p3_pure_lowering_matrix, cases[5].kind);
    try std.testing.expectEqual(Kind.rust_async_runner, cases[6].kind);
    try std.testing.expectEqual(Kind.compiler_fixture_matrix, cases[7].kind);
    try std.testing.expectEqual(Kind.compiler_compiled_fixture_matrix, cases[8].kind);
    try std.testing.expectEqual(Kind.compiler_auxiliary_matrix, cases[9].kind);
    try std.testing.expectEqual(Kind.compiler_compiled_trap_matrix, cases[10].kind);
    try std.testing.expectEqual(Kind.wasm_smoke_matrix, cases[11].kind);
    try std.testing.expectEqual(Kind.gc_default_matrix, cases[12].kind);
    try std.testing.expectEqual(Kind.component_template_validation, cases[13].kind);
    try std.testing.expectEqual(Kind.tool_matrix, cases[14].kind);
    try std.testing.expectEqual(Kind.external_dependency_negative_matrix, cases[15].kind);
    try std.testing.expectEqual(Kind.socket_abi_matrix, cases[16].kind);
    try std.testing.expectEqual(Kind.structural_gate, cases[17].kind);
    try std.testing.expectEqual(Kind.gc_core_oracle, cases[18].kind);
    try std.testing.expectEqual(Kind.gc_runtime_oracle, cases[19].kind);
    try std.testing.expectEqual(Kind.gc_assembly_matrix, cases[20].kind);
    try std.testing.expectEqual(Kind.map_core_probe, cases[21].kind);
    try std.testing.expectEqual(Kind.map_sync_component, cases[22].kind);
    try std.testing.expectEqual(Kind.map_async_component, cases[23].kind);
    try std.testing.expectEqual(Kind.gc_arc_inventory, cases[24].kind);
    try std.testing.expectEqual(Kind.gc_backend_firewall, cases[25].kind);
    try std.testing.expectEqual(Kind.gc_component_boundary, cases[26].kind);
}
