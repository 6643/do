const std = @import("std");
const lexer = @import("lexer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const producer = @import("codegen_component_two_list_owned_record_stream_producer.zig");

test "two-list owned-record producer plan admits measured list and ticket facts" {
    const source = @embedFile("test/check/782_g6_2_two_list_owned_record_producer_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const plan = try producer.TwoListOwnedRecordStreamProducerPlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("two-list-entry", plan.layout.name);
    try std.testing.expectEqual(@as(u32, 20), plan.layout.byte_size);
    try std.testing.expectEqual(@as(u32, 4), plan.layout.alignment);
    try std.testing.expectEqual(@as(u32, 0), plan.layout.fields[0].offset);
    try std.testing.expectEqual(@as(u32, 8), plan.layout.fields[1].offset);
    try std.testing.expectEqual(@as(u32, 16), plan.layout.fields[2].offset);
    try std.testing.expectEqual(@as(usize, 1), plan.contract.ownership.leaves.len);
    try std.testing.expectEqual(@as(u32, 16), plan.contract.ownership.leaves[0].handle_offset);
    try std.testing.expectEqual(@as(usize, 2), plan.contract.list_allocations.len);
    try std.testing.expectEqualStrings("first", plan.contract.list_allocations[0].path[0]);
    try std.testing.expectEqualStrings("second", plan.contract.list_allocations[1].path[0]);
}

test "two-list owned-record producer rejects a changed list element" {
    const source =
        \\make_ticket = @host_func("do:g6-2-owned-record-two-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-two-list-producer@0.1.0", "consume-via-stream", (StreamWriter<TwoListEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-two-list-producer/source/ticket", { .id i64 })
        \\TwoListEntry {
        \\    .first [u8]
        \\    .second [u32]
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
        error.UnsupportedP3TwoListOwnedRecordStreamProducer,
        producer.TwoListOwnedRecordStreamProducerPlan.analyze(tokens, registry),
    );
}
