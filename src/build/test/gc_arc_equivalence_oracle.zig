//! Explicit test-only ARC route used for semantic comparison snapshots.
const std = @import("std");
const codegen_pipeline = @import("../codegen_pipeline.zig");
const model = @import("../codegen_model.zig");
const imports = @import("../imports.zig");
const lexer = @import("../lexer.zig");
const parser = @import("../parser.zig");
const runtime_prelude_wat = @import("../runtime_prelude_wat.zig");

fn emit_string_data_memory(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    string_data: []const model.StringData,
    component_core: bool,
) !void {
    try runtime_prelude_wat.emit_string_data_memory(allocator, out, string_data, .{ .component_core = component_core });
}

fn emit_arc_runtime_prelude(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    string_data: []const model.StringData,
    struct_layouts: []const model.StructLayout,
) !void {
    try runtime_prelude_wat.emit_arc_runtime_prelude(allocator, out, string_data, struct_layouts);
}

const legacy_runtime: codegen_pipeline.LegacyRuntime = .{
    .emit_string_data_memory = emit_string_data_memory,
    .emit_legacy_runtime_prelude = emit_arc_runtime_prelude,
};

pub fn emit_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    return codegen_pipeline.emit_arc_equivalence_wat(allocator, program, tokens, module_graph, legacy_runtime, .{});
}

pub fn emit_test_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    return codegen_pipeline.emit_arc_equivalence_test_wat(allocator, program, tokens, module_graph, legacy_runtime);
}

test "ARC equivalence oracle: explicit test-only route" {
    const allocator = std.testing.allocator;
    const source =
        \\start() {
        \\    value text = "oracle"
        \\    _ = value
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);

    const wat = try emit_wat(allocator, program, tokens, null);
    defer allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "backend=arc-equivalence-oracle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") != null);
    std.debug.print("ARC equivalence oracle: explicit test-only route\n", .{});
}
