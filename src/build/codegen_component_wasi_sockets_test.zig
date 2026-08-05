const std = @import("std");
const lexer = @import("lexer.zig");
const sockets = @import("codegen_component_wasi_sockets.zig");

test "socket target accepts the bounded TCP source shape" {
    const source = @embedFile("wasi_sockets_tcp_fixture.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(sockets.Protocol.tcp, try sockets.analyze(tokens));
}

test "socket target rejects an unsupported socket operation" {
    const source = @embedFile("wasi_sockets_negative_fixture.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3WasiSocketsCreateBindDropComponent, sockets.analyze(tokens));
}

test "socket target emits the bounded UDP shape" {
    const source = @embedFile("wasi_sockets_udp_fixture.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(sockets.Protocol.udp, try sockets.analyze(tokens));
    const wat = try sockets.emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[static]udp-socket.create") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]udp-socket") != null);
}
