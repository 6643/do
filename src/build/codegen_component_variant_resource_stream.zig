const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

pub const VariantResourceStreamPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    event: p3_async_manifest.VariantEventLayout,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !VariantResourceStreamPlan {
        const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse
            return error.UnsupportedP3VariantResourceStream;
        const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3VariantResourceStream) {
            .variant_resource_stream_reader => |value| value,
            else => return error.UnsupportedP3VariantResourceStream,
        };
        if (!has_exact_signature(tokens)) return error.UnsupportedP3VariantResourceStream;
        return .{ .descriptor = descriptor, .event = shape.event };
    }
};

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = try VariantResourceStreamPlan.analyze(tokens, registry);
    return try allocator.dupe(u8, @embedFile("variant_resource_stream_canonical.wat"));
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = try VariantResourceStreamPlan.analyze(tokens, registry);
    return try allocator.dupe(u8, @embedFile("variant_resource_stream_canonical.wit"));
}

fn has_exact_signature(tokens: []const lexer.Token) bool {
    var index: usize = 0;
    while (index + 34 < tokens.len) : (index += 1) {
        if (tokens[index].kind != .ident or !std.mem.eql(u8, tokens[index + 1].lexeme, "=") or
            !std.mem.eql(u8, tokens[index + 2].lexeme, "@") or
            !std.mem.eql(u8, tokens[index + 3].lexeme, "host_func") or
            !std.mem.eql(u8, tokens[index + 4].lexeme, "(")) continue;
        if (!string_body_eq(tokens[index + 5], "do:variant-resource-stream-canonical@0.1.0") or
            !std.mem.eql(u8, tokens[index + 6].lexeme, ",") or
            !string_body_eq(tokens[index + 7], "read-via-stream") or
            !std.mem.eql(u8, tokens[index + 8].lexeme, ",")) continue;
        const expected = [_][]const u8{
            "(", ")", "-", ">", "Tuple", "<", "Stream", "<", "Ticket", "|", "nil", "|",
            "EventError", ">", ",", "Future", "<", "Result", "<", "nil", ",", "EventError", ">", ">", ">", ")",
        };
        for (expected, 0..) |value, offset| {
            if (!std.mem.eql(u8, tokens[index + 9 + offset].lexeme, value)) return false;
        }
        return true;
    }
    return false;
}

fn string_body_eq(token: lexer.Token, expected: []const u8) bool {
    if (token.kind != .string or token.lexeme.len < 2) return false;
    return std.mem.eql(u8, token.lexeme[1 .. token.lexeme.len - 1], expected);
}

test "variant resource stream emitter preserves measured ABI markers" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const plan = try VariantResourceStreamPlan.analyze(tokens, registry);
    try std.testing.expectEqual(@as(u32, 0), plan.event.tag_offset);
    try std.testing.expectEqual(@as(u32, 4), plan.event.payload_offset);
    try std.testing.expectEqual(@as(u32, 8), plan.event.byte_size);
    try std.testing.expectEqual(@as(u32, 4), plan.event.alignment);
    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[event-tag-offset]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[event-payload-offset]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $ticket-drop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "unreachable") != null);
}

test "variant resource stream emitter rejects a generic stream signature" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, EventError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedP3VariantResourceStream, VariantResourceStreamPlan.analyze(tokens, registry));
}
