const std = @import("std");
const manifest = @import("descriptor_manifest.zig");

const valid_source =
    "{\"schema\":1,\"toolchain\":\"wasm-tools 1.255.0\",\"descriptors\":[" ++
    "{\"id\":\"wasi:random/random.get-random-bytes@0.3.0-rc-2025-09-16/lift\"," ++
    "\"source\":\"src/build/p3_wit/random.wit\",\"world_source\":\"src/build/p3_wit/world.wit\"," ++
    "\"package\":\"wasi:random@0.3.0-rc-2025-09-16\",\"world\":\"imports\"," ++
    "\"interface\":\"random\",\"member\":\"get-random-bytes\",\"direction\":\"lift\"," ++
    "\"params\":[\"u64\"],\"result\":\"list<u8>\"," ++
    "\"source_sha256\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"," ++
    "\"canonical_import\":{\"module\":\"wasi:random/random@0.3.0-rc-2025-09-16\",\"name\":\"get-random-bytes\"}}]}";

test "descriptor manifest parses a bounded WIT record" {
    var parsed = try manifest.parse(std.testing.allocator, valid_source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 1), parsed.document.schema);
    try std.testing.expectEqualStrings("wasm-tools 1.255.0", parsed.document.toolchain);
    try std.testing.expectEqual(@as(usize, 1), parsed.document.descriptors.len);
    const descriptor = parsed.document.descriptors[0];
    try std.testing.expectEqualStrings("imports", descriptor.world);
    try std.testing.expectEqualStrings("list<u8>", descriptor.result);
}

test "descriptor manifest rejects duplicate ids" {
    const duplicate = std.mem.replaceOwned(u8, std.testing.allocator, valid_source,
        "}]}", "},{\"id\":\"wasi:random/random.get-random-bytes@0.3.0-rc-2025-09-16/lift\"}]}") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer std.testing.allocator.free(duplicate);
    try std.testing.expectError(error.DuplicateDescriptorId, manifest.parse(std.testing.allocator, duplicate));
}

test "descriptor manifest rejects traversal paths" {
    const escaped = std.mem.replaceOwned(u8, std.testing.allocator, valid_source,
        "src/build/p3_wit/random.wit", "../random.wit") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer std.testing.allocator.free(escaped);
    try std.testing.expectError(error.DescriptorPathInvalid, manifest.parse(std.testing.allocator, escaped));
}

test "descriptor manifest rejects invalid source hashes" {
    const invalid = std.mem.replaceOwned(u8, std.testing.allocator, valid_source,
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "sha256:bad") catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer std.testing.allocator.free(invalid);
    try std.testing.expectError(error.DescriptorHashInvalid, manifest.parse(std.testing.allocator, invalid));
}

test "descriptor manifest lookup rejects unknown ids" {
    var parsed = try manifest.parse(std.testing.allocator, valid_source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectError(error.DescriptorNotFound, parsed.find_descriptor("missing"));
}
