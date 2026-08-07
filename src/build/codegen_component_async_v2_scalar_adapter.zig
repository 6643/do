const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const imports = @import("imports.zig");
const module_graph = @import("module_graph.zig");
const generated_scalar_plan = @import("codegen_generated_async_scalar_plan.zig");
const abi_types = @import("wit_abi_types.zig");
const abi_layout = @import("wit_abi_layout.zig");
const ownership_model = @import("wit_abi_ownership.zig");
const async_model = @import("wit_abi_async.zig");
const v2_emitter = @import("codegen_component_async_v2_scalar_emitter.zig");

pub const ScalarAdapterPlan = struct {
    scalar: generated_scalar_plan.GeneratedAsyncScalarPlan,
    abi_type: abi_types.AbiType,
    layout: abi_layout.LayoutPlan,
    ownership: ownership_model.OwnershipPlan,
    async_plan: async_model.AsyncPlan,

    pub fn deinit(self: *ScalarAdapterPlan, allocator: std.mem.Allocator) void {
        self.scalar.deinit(allocator);
        self.abi_type.deinit();
        self.layout.deinit();
        self.ownership.deinit(allocator);
        self.async_plan.deinit(allocator);
        self.* = undefined;
    }

    pub fn emit_component_wat(self: *const ScalarAdapterPlan, allocator: std.mem.Allocator) ![]u8 {
        return v2_emitter.emit_scalar_i64(allocator, self.scalar, self.layout);
    }
};

pub fn analyze(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) !ScalarAdapterPlan {
    var scalar = try generated_scalar_plan.analyze(allocator, program, tokens, graph);
    errdefer scalar.deinit(allocator);

    const payload = scalar.payload;
    if (!std.mem.eql(u8, scalar.host_locator, "do:generic-async-scalar-i64-probe/host@0.1.0") or
        !std.mem.eql(u8, scalar.host_member, "completion") or
        !std.mem.eql(u8, payload.core_type, "i64") or
        payload.offset != 16 or payload.byte_size != 8 or payload.alignment != 8 or
        !std.mem.eql(u8, payload.encoding, "core-s64"))
    {
        return error.UnsupportedGenericAbiV2Scalar;
    }

    var abi_type = abi_types.AbiType.scalar(allocator, .i64);
    errdefer abi_type.deinit();
    var layout = try abi_layout.LayoutPlan.scalar(allocator, &abi_type, .{
        .offset = payload.offset,
        .byte_size = payload.byte_size,
        .alignment = payload.alignment,
        .core_type = .i64,
    });
    errdefer layout.deinit();

    const bindings = [_]ownership_model.ResourceBinding{};
    const operations = [_]ownership_model.Operation{};
    var ownership = try ownership_model.build(allocator, &bindings, &operations);
    errdefer ownership.deinit(allocator);

    const endpoints = [_]async_model.EndpointSpec{
        .{ .name = "first", .kind = .future },
        .{ .name = "second", .kind = .future },
    };
    const events = [_]async_model.Event{
        .{ .ready = .{ .name = "first" } },
        .{ .consume = .{ .name = "first" } },
        .{ .cancel = .{ .name = "second" } },
    };
    var async_plan = try async_model.build(allocator, &endpoints, &events);
    errdefer async_plan.deinit(allocator);

    return .{
        .scalar = scalar,
        .abi_type = abi_type,
        .layout = layout,
        .ownership = ownership,
        .async_plan = async_plan,
    };
}

/// Test helper for the pinned generated i64 manifest. Production graph loading
/// owns the same fields; this keeps the v2 unit test independent of filesystem IO.
pub fn test_i64_graph(allocator: std.mem.Allocator) !imports.ModuleGraph {
    const lowerings = try allocator.alloc(module_graph.GeneratedAsyncLowering, 1);
    errdefer allocator.free(lowerings);
    lowerings[0] = .{
        .locator = try allocator.dupe(u8, "do:generic-async-scalar-i64-probe/host@0.1.0"),
        .member = try allocator.dupe(u8, "completion"),
        .source_signature = try allocator.dupe(u8, "() -> Future<i64>"),
        .wit_package = try allocator.dupe(u8, "do:generic-async-scalar-i64-probe@0.1.0"),
        .wit_world = try allocator.dupe(u8, "probe"),
        .wit_interface = try allocator.dupe(u8, "host"),
        .wit_member = try allocator.dupe(u8, "completion"),
        .async_import_module = try allocator.dupe(u8, "do:generic-async-scalar-i64-probe/host@0.1.0"),
        .async_import_name = try allocator.dupe(u8, "[async-lower][future-read-0]completion"),
        .completion = try allocator.dupe(u8, "completion"),
        .wit_sha256 = [_]u8{0} ** 32,
        .payload = .{
            .core_type = try allocator.dupe(u8, "i64"),
            .offset = 16,
            .byte_size = 8,
            .alignment = 8,
            .encoding = try allocator.dupe(u8, "core-s64"),
        },
    };
    return .{
        .allocator = allocator,
        .dep_root = "",
        .modules = &.{},
        .generated_async_lowerings = lowerings,
    };
}

pub fn test_u32_graph(allocator: std.mem.Allocator) !imports.ModuleGraph {
    const lowerings = try allocator.alloc(module_graph.GeneratedAsyncLowering, 1);
    errdefer allocator.free(lowerings);
    lowerings[0] = .{
        .locator = try allocator.dupe(u8, "do:generic-async-scalar-probe/host@0.1.0"),
        .member = try allocator.dupe(u8, "completion"),
        .source_signature = try allocator.dupe(u8, "() -> Future<u32>"),
        .wit_package = try allocator.dupe(u8, "do:generic-async-scalar-probe@0.1.0"),
        .wit_world = try allocator.dupe(u8, "probe"),
        .wit_interface = try allocator.dupe(u8, "host"),
        .wit_member = try allocator.dupe(u8, "completion"),
        .async_import_module = try allocator.dupe(u8, "do:generic-async-scalar-probe/host@0.1.0"),
        .async_import_name = try allocator.dupe(u8, "[async-lower][future-read-0]completion"),
        .completion = try allocator.dupe(u8, "completion"),
        .wit_sha256 = [_]u8{0} ** 32,
        .payload = .{
            .core_type = try allocator.dupe(u8, "i32"),
            .offset = 12,
            .byte_size = 4,
            .alignment = 4,
            .encoding = try allocator.dupe(u8, "core-u32"),
        },
    };
    return .{
        .allocator = allocator,
        .dep_root = "",
        .modules = &.{},
        .generated_async_lowerings = lowerings,
    };
}

test "v2 scalar adapter rejects the existing u32 shape" {
    const source = @embedFile("test/check/430_generated_async_scalar.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try test_u32_graph(std.testing.allocator);
    defer graph.deinit();
    try std.testing.expectError(error.UnsupportedGenericAbiV2Scalar, analyze(std.testing.allocator, program, tokens, &graph));
}
