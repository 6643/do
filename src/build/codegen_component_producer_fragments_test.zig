const std = @import("std");
const fragments = @import("codegen_component_producer_fragments.zig");

const prefix = "(module\n";
const payload = "  ;; payload [producer-record-byte-size] 4\n";
const lifecycle = "  ;; lifecycle [producer-record-transfer]\n";
const metadata = "  ;; metadata [producer-stream-capacity] 1\n";
const suffix = ")\n";
const template = prefix ++ payload ++ lifecycle ++ metadata ++ suffix;
const direct_template: []const u8 = @embedFile("owned_record_stream_producer_template.wat");

const direct_fragments = [_]fragments.Fragment{
    .{ .name = "module-prefix", .kind = .prefix, .span = .{ .start = 0, .end = prefix.len }, .required_markers = &.{}, .order = 0 },
    .{ .name = "record-payload", .kind = .payload, .span = .{ .start = prefix.len, .end = prefix.len + payload.len }, .required_markers = &.{"[producer-record-byte-size] 4"}, .order = 1 },
    .{ .name = "record-lifecycle", .kind = .lifecycle, .span = .{ .start = prefix.len + payload.len, .end = prefix.len + payload.len + lifecycle.len }, .required_markers = &.{"[producer-record-transfer]"}, .order = 2 },
    .{ .name = "stream-metadata", .kind = .metadata, .span = .{ .start = prefix.len + payload.len + lifecycle.len, .end = prefix.len + payload.len + lifecycle.len + metadata.len }, .required_markers = &.{"[producer-stream-capacity] 1"}, .order = 3 },
    .{ .name = "module-suffix", .kind = .suffix, .span = .{ .start = template.len - suffix.len, .end = template.len }, .required_markers = &.{}, .order = 4 },
};

test "producer fragment table accepts direct route coverage" {
    try fragments.validate_fragment_table(template, &direct_fragments);
}

test "producer fragment assembly preserves direct route bytes" {
    const assembled = try fragments.assemble(std.testing.allocator, template, &direct_fragments);
    defer std.testing.allocator.free(assembled);
    try std.testing.expectEqualStrings(template, assembled);
}

test "producer fragment assembly preserves the embedded direct route template" {
    const payload_start = marker_offset("(func $layout-markers");
    const lifecycle_start = marker_offset("(func $wait-on-subtask");
    const metadata_start = marker_offset("(func $cleanup");
    const suffix_start = direct_template.len - 2;
    const required = [_][]const u8{
        "[producer-record-byte-size] 4",
        "[producer-record-ticket-offset] 0",
        "[producer-stream-capacity] 1",
        "[producer-ticket-seed] 111",
        "[producer-record-transfer]",
        "[producer-resource-drop-exactly-once]",
        "[producer-child-before-parent-cleanup]",
    };
    const direct = [_]fragments.Fragment{
        .{ .name = "direct-prefix", .kind = .prefix, .span = .{ .start = 0, .end = payload_start }, .required_markers = &.{}, .order = 0 },
        .{ .name = "direct-payload", .kind = .payload, .span = .{ .start = payload_start, .end = lifecycle_start }, .required_markers = &required, .order = 1 },
        .{ .name = "direct-lifecycle", .kind = .lifecycle, .span = .{ .start = lifecycle_start, .end = metadata_start }, .required_markers = &.{}, .order = 2 },
        .{ .name = "direct-metadata", .kind = .metadata, .span = .{ .start = metadata_start, .end = suffix_start }, .required_markers = &.{}, .order = 3 },
        .{ .name = "direct-suffix", .kind = .suffix, .span = .{ .start = suffix_start, .end = direct_template.len }, .required_markers = &.{}, .order = 4 },
    };
    const assembled = try fragments.assemble(std.testing.allocator, direct_template, &direct);
    defer std.testing.allocator.free(assembled);
    try std.testing.expectEqualSlices(u8, direct_template, assembled);
}

test "producer fragment table rejects an empty table" {
    try std.testing.expectError(error.EmptyTable, fragments.validate_fragment_table(template, &.{}));
}

test "producer fragment table rejects an empty name" {
    var changed = direct_fragments;
    changed[1].name = "";
    try std.testing.expectError(error.EmptyName, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment table rejects an invalid span" {
    var changed = direct_fragments;
    changed[1].span.end = changed[1].span.start;
    try std.testing.expectError(error.InvalidSpan, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment table rejects a span outside the template" {
    var changed = direct_fragments;
    changed[1].span.end = @intCast(template.len + 1);
    try std.testing.expectError(error.SpanOutsideTemplate, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment table rejects a coverage gap" {
    var changed = direct_fragments;
    changed[2].span.start += 1;
    try std.testing.expectError(error.FragmentGap, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment table rejects overlapping coverage" {
    var changed = direct_fragments;
    changed[2].span.start -= 1;
    try std.testing.expectError(error.FragmentOverlap, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment table rejects order drift" {
    var changed = direct_fragments;
    changed[2].order = 3;
    try std.testing.expectError(error.OrderDrift, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment table rejects invalid kind order" {
    var changed = direct_fragments;
    changed[2].kind = .prefix;
    try std.testing.expectError(error.InvalidKindOrder, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment table rejects one whole-template fragment" {
    const whole = [_]fragments.Fragment{.{
        .name = "whole-template",
        .kind = .prefix,
        .span = .{ .start = 0, .end = template.len },
        .required_markers = &.{"[producer-record-transfer]"},
        .order = 0,
    }};
    try std.testing.expectError(error.WholeTemplateFragment, fragments.validate_fragment_table(template, &whole));
}

test "producer fragment table rejects a missing marker" {
    var changed = direct_fragments;
    changed[1].required_markers = &.{"[producer-record-transfer]"};
    try std.testing.expectError(error.MissingMarker, fragments.validate_fragment_table(template, &changed));
}

test "producer fragment assembly fails closed for invalid coverage" {
    var changed = direct_fragments;
    changed[2].span.start += 1;
    try std.testing.expectError(error.FragmentGap, fragments.assemble(std.testing.allocator, template, &changed));
}

test "producer fragment assembly propagates allocator exhaustion without an artifact" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, fragments.assemble(failing.allocator(), template, &direct_fragments));
    try std.testing.expectEqual(@as(usize, 0), failing.allocations);
    try std.testing.expectEqual(@as(usize, 0), failing.deallocations);
}

fn marker_offset(marker: []const u8) u32 {
    return @intCast(std.mem.indexOf(u8, direct_template, marker) orelse unreachable);
}
