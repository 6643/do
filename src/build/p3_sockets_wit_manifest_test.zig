const std = @import("std");
const manifest = @import("p3_sockets_wit_manifest.zig");

test "pinned sockets source validates and exposes the admitted operations" {
    try manifest.validate();
    try std.testing.expectEqualStrings("wasi:sockets@0.3.0-rc-2025-09-16", manifest.package_revision);
    try std.testing.expect(manifest.has_operation("tcp-socket.create"));
    try std.testing.expect(manifest.has_operation("tcp-socket.bind"));
    try std.testing.expect(manifest.has_operation("udp-socket.create"));
    try std.testing.expect(manifest.has_operation("udp-socket.bind"));
    try std.testing.expect(manifest.has_operation("[resource-drop]tcp-socket"));
    try std.testing.expect(manifest.has_operation("[resource-drop]udp-socket"));
    try std.testing.expect(!manifest.has_operation("tcp-socket.connect"));
    try std.testing.expect(!manifest.has_operation("tcp-socket.listen"));
}

test "socket manifest pins the source hashes" {
    try manifest.validate();
    try std.testing.expectEqual(@as(usize, 64), manifest.types_sha256.len);
    try std.testing.expectEqual(@as(usize, 64), manifest.world_sha256.len);
}
