const std = @import("std");
const lexer = @import("lexer.zig");
const plan = @import("codegen_component_async_map_plan.zig");

const matching_source =
    \\HashMap = @lib("hash_map.do", HashMap)
    \\empty_hash_map = @lib("hash_map.do", empty_hash_map)
    \\hash_put = @lib("hash_map.do", hash_put)
    \\submit = @host_async_func("demo:map-async-probe/api@0.1.0", "submit", (HashMap<u32, u32>) -> u32)
    \\
    \\helper(values HashMap<u32, u32>) -> u32 {
    \\    pending Future<u32> = submit(values)
    \\    return @await(pending)
    \\}
    \\
    \\run() -> u32 {
    \\    key u32 = 0
    \\    value u32 = 0
    \\    values HashMap<u32, u32> = empty_hash_map(key, value)
    \\    values = hash_put(values, 7, 70)
    \\    values = hash_put(values, 9, 90)
    \\    child Future<u32> = @async(helper(values))
    \\    return @await(child)
    \\}
;

test "async map plan accepts the pinned source" {
    const tokens = try lexer.tokenize(std.testing.allocator, matching_source);
    defer std.testing.allocator.free(tokens);
    var result = try plan.analyze(std.testing.allocator, tokens);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("run", result.root_name);
}

test "async map plan accepts the pinned source topology" {
    const tokens = try lexer.tokenize(std.testing.allocator, matching_source);
    defer std.testing.allocator.free(tokens);
    var result = try plan.analyze(std.testing.allocator, tokens);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("run", result.root_name);
    try std.testing.expectEqualStrings("helper", result.helper_name);
    try std.testing.expectEqualStrings("submit", result.host_name);
    try std.testing.expectEqualStrings("HashMap<u32, u32>", result.shape.source_param);
    try std.testing.expectEqualStrings("u32", result.shape.source_result);
}

test "async map plan rejects a non-u32 map value" {
    const source = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        matching_source,
        "HashMap<u32, u32>) -> u32",
        "HashMap<u32, u64>) -> u32",
    );
    defer std.testing.allocator.free(source);
    try expect_rejected(source, .type_unsupported);
}

test "async map plan rejects dynamic map construction" {
    const source = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        matching_source,
        "empty_hash_map(key, value)",
        "empty_hash_map(1, value)",
    );
    defer std.testing.allocator.free(source);
    try expect_rejected(source, .dynamic_map);
}

test "async map plan rejects an extra pair" {
    const source = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        matching_source,
        "    child Future<u32> = @async(helper(values))",
        "    values = hash_put(values, 11, 110)\n    child Future<u32> = @async(helper(values))",
    );
    defer std.testing.allocator.free(source);
    try expect_rejected(source, .extra_pair);
}

test "async map plan rejects a synchronous host marker" {
    const source = try std.mem.replaceOwned(u8, std.testing.allocator, matching_source, "@host_async_func", "@host_func");
    defer std.testing.allocator.free(source);
    try expect_rejected(source, .marker_mismatch);
}

test "async map plan rejects a second await" {
    const source = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        matching_source,
        "    return @await(child)",
        "    return @await(child)\n    return @await(child)",
    );
    defer std.testing.allocator.free(source);
    try expect_rejected(source, .multiple_children);
}

fn expect_rejected(source: []const u8, expected: plan.RejectReason) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncMapComponent, plan.analyze(std.testing.allocator, tokens));
    const reason = try plan.rejection_reason(std.testing.allocator, tokens);
    try std.testing.expect(reason != null);
    try std.testing.expectEqual(expected, reason.?);
}
