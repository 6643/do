const std = @import("std");
const abi_types = @import("wit_abi_types.zig");
const abi_layout = @import("wit_abi_layout.zig");
const ownership = @import("wit_abi_ownership.zig");
const async_model = @import("wit_abi_async.zig");
const v2_emitter = @import("codegen_component_async_v2_emitter.zig");
const lexer = @import("lexer.zig");
const manifest = @import("p3_async_manifest.zig");
const v1 = @import("codegen_component_variant_resource_stream.zig");
const scalar_v2 = @import("codegen_component_async_v2_scalar_adapter.zig");

pub const AdapterPlan = struct {
    descriptor: manifest.Descriptor,
    variant_shape: manifest.VariantResourceStreamShape,
    layout: abi_layout.LayoutPlan,
    ownership: ownership.OwnershipPlan,
    async_plan: async_model.AsyncPlan,

    pub fn deinit(self: *AdapterPlan, allocator: std.mem.Allocator) void {
        self.layout.deinit();
        self.ownership.deinit(allocator);
        self.async_plan.deinit(allocator);
    }

    pub fn emit_component_wat(self: *const AdapterPlan, allocator: std.mem.Allocator) ![]u8 {
        return try v2_emitter.emit_variant_resource_stream(
            allocator,
            self.descriptor,
            self.variant_shape,
            self.layout,
        );
    }
};

pub fn analyze(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    registry: manifest.Registry,
) !AdapterPlan {
    const descriptor_plan = try v1.VariantResourceStreamPlan.analyze(tokens, registry);
    const variant_shape = switch (manifest.lowering_shape(descriptor_plan.descriptor) orelse return error.UnsupportedP3VariantResourceStream) {
        .variant_resource_stream_reader => |value| value,
        else => return error.UnsupportedP3VariantResourceStream,
    };
    const shape = variant_shape.event;
    if (shape.tag_offset != 0 or shape.payload_offset != 4 or shape.byte_size != 8 or shape.alignment != 4 or shape.variants.len != 3) {
        return error.UnsupportedP3VariantResourceStream;
    }
    if (!std.mem.eql(u8, shape.variants[0].payload orelse "", "own<ticket>") or
        shape.variants[1].payload != null or
        !std.mem.eql(u8, shape.variants[2].payload orelse "", "error-code"))
    {
        return error.UnsupportedP3VariantResourceStream;
    }

    var ticket = try abi_types.AbiType.resource(allocator, "ticket", .own);
    defer ticket.deinit();
    var error_code = abi_types.AbiType.scalar(allocator, .i32);
    defer error_code.deinit();
    var event = try abi_types.AbiType.variant(allocator, &.{
        .{ .tag = shape.variants[0].tag, .name = shape.variants[0].name, .payload = &ticket },
        .{ .tag = shape.variants[1].tag, .name = shape.variants[1].name, .payload = null },
        .{ .tag = shape.variants[2].tag, .name = shape.variants[2].name, .payload = &error_code },
    });
    defer event.deinit();

    var layout = try abi_layout.LayoutPlan.variant(allocator, &event, .{
        .tag_offset = shape.tag_offset,
        .payload_offset = shape.payload_offset,
        .byte_size = shape.byte_size,
        .alignment = shape.alignment,
        .cases = &.{
            .{ .name = shape.variants[0].name, .tag = shape.variants[0].tag, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            .{ .name = shape.variants[1].name, .tag = shape.variants[1].tag, .payload_required = false, .payload = null },
            .{ .name = shape.variants[2].name, .tag = shape.variants[2].tag, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
        },
    });
    errdefer layout.deinit();

    const bindings = [_]ownership.ResourceBinding{try ownership.ResourceBinding.init("ticket", &ticket)};
    const ownership_operations = [_]ownership.Operation{
        .{ .move = .{ .source = "ticket", .destination = "event_ticket" } },
        .{ .release = .{ .name = "event_ticket" } },
    };
    var ownership_plan = try ownership.build(allocator, &bindings, &ownership_operations);
    errdefer ownership_plan.deinit(allocator);

    const endpoints = [_]async_model.EndpointSpec{
        .{ .name = "stream", .kind = .stream },
        .{ .name = "future", .kind = .future },
        .{ .name = "ticket", .kind = .resource },
    };
    const async_events = [_]async_model.Event{
        .{ .ready = .{ .name = "stream" } },
        .{ .consume = .{ .name = "stream" } },
        .{ .completion_error = .{ .name = "future" } },
        .{ .consume = .{ .name = "future" } },
        .{ .drop = .{ .name = "ticket" } },
    };
    var async_plan = try async_model.build(allocator, &endpoints, &async_events);
    errdefer async_plan.deinit(allocator);

    return .{
        .descriptor = descriptor_plan.descriptor,
        .variant_shape = variant_shape,
        .layout = layout,
        .ownership = ownership_plan,
        .async_plan = async_plan,
    };
}

test "v2 variant adapter matches v1 component contract facts" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const v1_wat = try v1.emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(v1_wat);
    var v2 = try analyze(std.testing.allocator, tokens, registry);
    defer v2.deinit(std.testing.allocator);
    const v2_wat = try v2.emit_component_wat(std.testing.allocator);
    defer std.testing.allocator.free(v2_wat);

    try expect_contract(v1_wat);
    try expect_contract(v2_wat);
    try std.testing.expect(v2_wat.len > 0);
    try std.testing.expect(!std.mem.eql(u8, v1_wat, v2_wat));
}

test "v2 variant adapter rejects a non-canonical signature before emitting" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, EventError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedP3VariantResourceStream, analyze(std.testing.allocator, tokens, registry));
}

test "v2 scalar adapter emits an independent Future<i64> artifact" {
    const source = @embedFile("test/check/431_generated_async_scalar_i64.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try @import("parser.zig").parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try scalar_v2.test_i64_graph(std.testing.allocator);
    defer graph.deinit();

    var v2 = try scalar_v2.analyze(std.testing.allocator, program, tokens, &graph);
    defer v2.deinit(std.testing.allocator);
    const wat = try v2.emit_component_wat(std.testing.allocator);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "generic ABI v2 independent scalar-i64 emitter template") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[scalar-payload] offset=16 byte-size=8 alignment=8 encoding=core-s64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store") != null);
}

fn expect_contract(wat: []const u8) !void {
    const required_imports = [_][]const u8{
        "[async-lower][stream-read-0]read-via-stream",
        "[stream-drop-readable-0]read-via-stream",
        "[async-lower][future-read-1]read-via-stream",
        "[future-drop-readable-1]read-via-stream",
        "[resource-drop]ticket",
    };
    for (required_imports) |name| try std.testing.expect(std.mem.indexOf(u8, wat, name) != null);
    for ([_][]const u8{ "[event-tag-offset]", "[event-payload-offset]", "[event-size]", "[event-alignment]" }) |marker| {
        try std.testing.expect(std.mem.indexOf(u8, wat, marker) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $release-ticket") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $cleanup") != null);
}
