const std = @import("std");

const canonical_core_wat = @embedFile("owned_record_stream_producer_template.wat");

pub const CounterError = error{
    MissingAnchor,
    DuplicateAnchor,
    InvalidCanonicalArtifact,
    OutOfMemory,
};

const frame_alloc_anchor = "(func $frame-alloc (result i32)";
const frame_free_anchor = "(func $frame-free (param $frame i32)";
const memory_anchor = "  (memory (export \"memory\") 2)";

pub fn instrument(allocator: std.mem.Allocator, canonical_wat: []const u8) CounterError![]u8 {
    try validate_anchor(canonical_wat, frame_alloc_anchor);
    try validate_anchor(canonical_wat, frame_free_anchor);
    try validate_anchor(canonical_wat, memory_anchor);
    if (!std.mem.eql(u8, canonical_wat, canonical_core_wat)) return error.InvalidCanonicalArtifact;
    for ([_][]const u8{
        "[producer-record-byte-size] 4",
        "[producer-record-ticket-offset] 0",
        "[producer-stream-capacity] 1",
        "[producer-ticket-seed] 111",
        "[producer-record-transfer]",
        "[producer-resource-drop-exactly-once]",
        "[producer-child-before-parent-cleanup]",
    }) |marker| {
        if (count(canonical_wat, marker) == 0) return error.InvalidCanonicalArtifact;
    }

    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    const memory_position = std.mem.indexOf(u8, canonical_wat, memory_anchor) orelse return error.MissingAnchor;
    const alloc_position = std.mem.indexOfPos(u8, canonical_wat, memory_position + memory_anchor.len, frame_alloc_anchor) orelse return error.MissingAnchor;
    const free_position = std.mem.indexOfPos(u8, canonical_wat, alloc_position + frame_alloc_anchor.len, frame_free_anchor) orelse return error.MissingAnchor;
    try append_segment(allocator, &output, canonical_wat, 0, memory_anchor, instrumentation_prefix());
    try append_segment(allocator, &output, canonical_wat, memory_position + memory_anchor.len, frame_alloc_anchor, frame_alloc_body());
    try append_segment(allocator, &output, canonical_wat, alloc_position + frame_alloc_anchor.len, frame_free_anchor, frame_free_body());
    output.appendSlice(allocator, canonical_wat[free_position + frame_free_anchor.len ..]) catch return error.OutOfMemory;
    return output.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

fn validate_anchor(wat: []const u8, anchor: []const u8) CounterError!void {
    switch (count(wat, anchor)) {
        0 => return error.MissingAnchor,
        1 => {},
        else => return error.DuplicateAnchor,
    }
}

fn append_segment(allocator: std.mem.Allocator, output: *std.ArrayList(u8), wat: []const u8, start: usize, anchor: []const u8, insertion: []const u8) CounterError!void {
    const position = std.mem.indexOfPos(u8, wat, start, anchor) orelse return error.MissingAnchor;
    output.appendSlice(allocator, wat[start .. position + anchor.len]) catch return error.OutOfMemory;
    output.appendSlice(allocator, insertion) catch return error.OutOfMemory;
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

fn instrumentation_prefix() []const u8 {
    return
    \\  ;; [test-only-runtime-counters]
    \\  (type $runtime-counters (func (result i32 i32 i32 i32)))
    \\  (global $runtime-counter-frame-allocations (mut i32) (i32.const 0))
    \\  (global $runtime-counter-frame-releases (mut i32) (i32.const 0))
    \\  (global $runtime-counter-list-allocations (mut i32) (i32.const 0))
    \\  (global $runtime-counter-list-releases (mut i32) (i32.const 0))
    \\  (func $runtime-counters (type $runtime-counters)
    \\    global.get $runtime-counter-frame-allocations
    \\    global.get $runtime-counter-frame-releases
    \\    global.get $runtime-counter-list-allocations
    \\    global.get $runtime-counter-list-releases
    \\  )
    \\  (export "runtime-counters" (func $runtime-counters))
    ;
}

fn frame_alloc_body() []const u8 {
    return
    \\    global.get $runtime-counter-frame-allocations
    \\    i32.const 1
    \\    i32.add
    \\    global.set $runtime-counter-frame-allocations
    ;
}

fn frame_free_body() []const u8 {
    return
    \\    global.get $runtime-counter-frame-releases
    \\    i32.const 1
    \\    i32.add
    \\    global.set $runtime-counter-frame-releases
    ;
}
