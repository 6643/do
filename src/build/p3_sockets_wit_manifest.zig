const std = @import("std");

pub const package_revision = "wasi:sockets@0.3.0-rc-2025-09-16";
pub const source_path = "src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets";
pub const types_sha256 = "05c39ed24afdf1d4b1693851d462d958bfd8c542c573b65350b9ceb2e27f8d65";
pub const world_sha256 = "4da84a1f4efd9c9f45bdeb93b8d6310e5bdb053f0dc6ec5f2d48868102de1c4e";

const types_path = "p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets/types.wit";
const world_path = "p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets/world.wit";

const admitted_operations = [_][]const u8{
    "tcp-socket.create",
    "tcp-socket.bind",
    "udp-socket.create",
    "udp-socket.bind",
    "[resource-drop]tcp-socket",
    "[resource-drop]udp-socket",
};

/// Validate the package revision and the exact source facts used by the
/// bounded create/bind/drop Component target.
pub fn validate() !void {
    const types = @embedFile(types_path);
    const world = @embedFile(world_path);
    try verify_sha256(types, types_sha256);
    try verify_sha256(world, world_sha256);
    if (std.mem.indexOf(u8, world, "package " ++ package_revision ++ ";") == null) {
        return error.InvalidPinnedSocketsWit;
    }
    if (std.mem.indexOf(u8, world, "import types;") == null) {
        return error.InvalidPinnedSocketsWit;
    }
    const required = [_][]const u8{
        "resource tcp-socket",
        "resource udp-socket",
        "create: static func(address-family: ip-address-family) -> result<tcp-socket, error-code>;",
        "create: static func(address-family: ip-address-family) -> result<udp-socket, error-code>;",
        "bind: func(local-address: ip-socket-address) -> result<_, error-code>;",
        "variant ip-socket-address",
        "enum ip-address-family",
    };
    for (required) |needle| {
        if (std.mem.indexOf(u8, types, needle) == null) return error.InvalidPinnedSocketsWit;
    }
}

pub fn has_operation(name: []const u8) bool {
    for (admitted_operations) |operation| {
        if (std.mem.eql(u8, operation, name)) return true;
    }
    return false;
}

fn verify_sha256(bytes: []const u8, expected: []const u8) !void {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});

    var actual: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
    for (digest, 0..) |byte, index| {
        actual[index * 2] = hex_digit(byte >> 4);
        actual[index * 2 + 1] = hex_digit(byte & 0x0f);
    }
    if (!std.mem.eql(u8, &actual, expected)) return error.InvalidPinnedSocketsWit;
}

fn hex_digit(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}

test "socket manifest rejects an unadmitted operation" {
    try std.testing.expect(!has_operation("tcp-socket.connect"));
    try std.testing.expect(!has_operation("udp-socket.receive"));
}
