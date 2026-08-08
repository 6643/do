const std = @import("std");
const lexer = @import("lexer.zig");
const plan = @import("codegen_component_future_owned_plan.zig");

const positive_source =
    \\read = @host_func("do:future-owned-canonical/source@0.1.0", "read", () -> Future<Ticket>)
    \\Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })
    \\run(mode u32) -> nil {
    \\    pending Future<Ticket> = read()
    \\    ticket Ticket = @await(pending)
    \\}
    \\start() {}
;

test "future-owned plan admits the exact private source shape" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    var result = try plan.analyze(std.testing.allocator, tokens);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("run", result.root_name);
    try std.testing.expectEqualStrings("mode", result.mode_name);
    try std.testing.expectEqualStrings("read", result.host_name);
    try std.testing.expectEqualStrings("Ticket", result.ticket_type_name);
    try std.testing.expectEqualStrings("pending", result.future_name);
    try std.testing.expectEqualStrings("ticket", result.await_name);
    try std.testing.expectEqual(@as(u32, 12), result.payload_offset);
    try std.testing.expectEqual(@as(u32, 16), result.resource_offset);
    try std.testing.expectEqual(@as(u32, 20), result.presence_offset);
}

test "future-owned plan rejects an unknown host descriptor" {
    const source =
        \\read = @host_func("do:future-owned-canonical/source@0.1.0", "missing", () -> Future<Ticket>)
        \\Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })
        \\run(mode u32) -> nil {
        \\    pending Future<Ticket> = read()
        \\    ticket Ticket = @await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3OwnedFutureComponent, plan.analyze(std.testing.allocator, tokens));
}

test "future-owned plan rejects a copied payload" {
    const source =
        \\read = @host_func("do:future-owned-canonical/source@0.1.0", "read", () -> Future<i32>)
        \\Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })
        \\run(mode u32) -> nil {
        \\    pending Future<i32> = read()
        \\    value i32 = @await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3OwnedFutureComponent, plan.analyze(std.testing.allocator, tokens));
}

test "future-owned plan rejects a second await" {
    const source =
        \\read = @host_func("do:future-owned-canonical/source@0.1.0", "read", () -> Future<Ticket>)
        \\Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })
        \\run(mode u32) -> nil {
        \\    pending Future<Ticket> = read()
        \\    ticket Ticket = @await(pending)
        \\    second Future<Ticket> = read()
        \\    second_ticket Ticket = @await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3OwnedFutureComponent, plan.analyze(std.testing.allocator, tokens));
}

test "future-owned plan rejects an async declaration" {
    const source =
        \\read = @host_func("do:future-owned-canonical/source@0.1.0", "read", () -> Future<Ticket>)
        \\Ticket = @wasi_resource("do:future-owned-canonical/source/ticket", { .id i64 })
        \\async run(mode u32) -> nil {
        \\    pending Future<Ticket> = read()
        \\    ticket Ticket = @await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3OwnedFutureComponent, plan.analyze(std.testing.allocator, tokens));
}
