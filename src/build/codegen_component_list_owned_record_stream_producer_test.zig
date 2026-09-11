const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const producer = @import("codegen_component_list_owned_record_stream_producer.zig");

test "list-owned-record producer plan admits measured list and ticket facts" {
    const source = @embedFile("test/check/771_g6_2_list_owned_record_producer_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const plan = try producer.ListOwnedRecordStreamProducerPlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("list-entry", plan.layout.name);
    try std.testing.expectEqual(@as(u32, 12), plan.layout.byte_size);
    try std.testing.expectEqual(@as(u32, 4), plan.layout.alignment);
    try std.testing.expectEqual(@as(u32, 0), plan.list_layout.pointer_offset);
    try std.testing.expectEqual(@as(u32, 4), plan.list_layout.length_offset);
    try std.testing.expectEqual(@as(u32, 4), plan.list_layout.element_stride);
    try std.testing.expectEqual(@as(u32, 3), plan.list_layout.max_items);
    try std.testing.expectEqual(@as(u32, 8), plan.layout.fields[1].offset);
    try std.testing.expectEqual(@as(usize, 1), plan.contract.ownership.leaves.len);
    try std.testing.expectEqual(@as(usize, 1), plan.contract.list_allocations.len);

    const wat = try producer.emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-transfer]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-list-release-exactly-once]") != null);
    const legacy_marker = "__" ++ "arc_";
    try std.testing.expect(std.mem.indexOf(u8, wat, legacy_marker) == null);

    const wit = try producer.emit_component_wit(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    const expected = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "../examples/p3-runtime/wit/g6-2-owned-record-list-producer.wit",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, wit);
}

test "list-owned-record producer rejects a changed list element" {
    const source =
        \\make_ticket = @host_func("do:g6-2-owned-record-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-list-producer@0.1.0", "consume-via-stream", (StreamWriter<ListEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-list-producer/source/ticket", { .id i64 })
        \\ListEntry {
        \\    .values [u8]
        \\    .ticket Ticket
        \\}
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.UnsupportedP3ListOwnedRecordStreamProducer,
        producer.ListOwnedRecordStreamProducerPlan.analyze(tokens, registry),
    );
}
