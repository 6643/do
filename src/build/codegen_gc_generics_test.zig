// Compile-only guard for the GC-specific generic collector boundary.
const std = @import("std");
const gc_generics = @import("codegen_gc_generics.zig");

test "GC generic collector is independently importable" {
    _ = gc_generics;
}

test "GC generic collector does not import legacy emitters" {
    const source = @embedFile("codegen_gc_generics.zig");
    const forbidden = [_][]const u8{
        "codegen_emit_call.zig",
        "codegen_emit_expression.zig",
        "codegen_emit_storage_values.zig",
        "codegen_emit_storage_operations.zig",
        "codegen_emit_struct.zig",
        "codegen_emit_struct_fields.zig",
        "codegen_emit_control.zig",
        "codegen_emit_union.zig",
        "codegen_ownership.zig",
        "ownership.zig",
        "ownership_facts.zig",
    };
    for (forbidden) |name| {
        try std.testing.expect(std.mem.indexOf(u8, source, name) == null);
    }
}
