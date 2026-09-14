const std = @import("std");
const counters = @import("codegen_component_producer_runtime_counters.zig");

const canonical_wat = @embedFile("owned_record_stream_producer_template.wat");

test "producer runtime counter instrumentation preserves canonical WAT" {
    const input = try std.testing.allocator.dupe(u8, canonical_wat);
    defer std.testing.allocator.free(input);
    const instrumented = try counters.instrument(std.testing.allocator, input);
    defer std.testing.allocator.free(instrumented);
    try std.testing.expectEqualStrings(canonical_wat, input);
    try std.testing.expect(std.mem.indexOf(u8, instrumented, "[test-only-runtime-counters]") != null);
    try std.testing.expectEqual(@as(usize, 4), count(instrumented, "(global $runtime-counter-"));
    try std.testing.expectEqual(@as(usize, 1), count(instrumented, "(export \"runtime-counters\""));
    try std.testing.expectEqual(@as(usize, 1), count(instrumented, "(func $runtime-counters (type"));
    try std.testing.expectEqual(@as(usize, 1), count(instrumented, "runtime-counter-event\" (func $runtime-counter-event"));
    try std.testing.expect(std.mem.indexOf(u8, instrumented, "(type $runtime-counters (func (result i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, instrumented, "i32.const 12\n    i32.store") != null);
    try std.testing.expect(std.mem.indexOf(u8, instrumented, "i32.const 1\n    call $runtime-counter-event") != null);
    try std.testing.expect(std.mem.indexOf(u8, instrumented, "i32.const 2\n    call $runtime-counter-event") != null);
    const runtime_import = std.mem.indexOf(u8, instrumented, "runtime-counter-event\" (func $runtime-counter-event") orelse return error.TestExpectedEqual;
    const memory = std.mem.indexOf(u8, instrumented, "(memory (export \"memory\") 2)") orelse return error.TestExpectedEqual;
    try std.testing.expect(runtime_import < memory);
}

test "owned record producer rejects invalid mode before allocating a frame" {
    const invalid_guard = "local.get $mode\n    i32.const 255\n    i32.eq\n    if\n      i32.const 1\n      i32.const 2\n      call $task-return\n      i32.const 0\n      return\n    end\n    call $frame-alloc";
    try std.testing.expect(std.mem.indexOf(u8, canonical_wat, invalid_guard) != null);
}

test "producer runtime counter instrumentation rejects missing anchors" {
    try std.testing.expectError(error.MissingAnchor, counters.instrument(std.testing.allocator, "(module)"));
}

test "producer runtime counter instrumentation rejects duplicate anchors" {
    const duplicate = canonical_wat ++ "\n(func $frame-alloc (result i32))\n";
    try std.testing.expectError(error.DuplicateAnchor, counters.instrument(std.testing.allocator, duplicate));
}

test "producer runtime counter instrumentation rejects drifted anchor" {
    const input = try std.testing.allocator.dupe(u8, canonical_wat);
    defer std.testing.allocator.free(input);
    const anchor = std.mem.indexOf(u8, input, "frame-alloc") orelse return error.TestExpectedEqual;
    input[anchor + "frame-".len] = '0';
    try std.testing.expectError(error.MissingAnchor, counters.instrument(std.testing.allocator, input));
}

fn count(haystack: []const u8, needle: []const u8) usize {
    var result: usize = 0;
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, offset, needle)) |found| {
        result += 1;
        offset = found + needle.len;
    }
    return result;
}
