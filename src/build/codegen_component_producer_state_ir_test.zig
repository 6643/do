const std = @import("std");
const facts = @import("codegen_component_producer_facts.zig");
const producer_contract = @import("codegen_component_producer_contract.zig");
const state_ir = @import("codegen_component_producer_state_ir.zig");

const path = [_][]const u8{"ticket"};
const fields = [_]facts.FrameFact{
    .{ .name = "tag", .offset = 0, .width = 4, .alignment = 4, .role = .result_tag },
    .{ .name = "state", .offset = 4, .width = 4, .alignment = 4, .role = .ownership_state },
};
const ownership = [_]facts.OwnershipFact{.{ .name = "ticket", .encoding = .scalar, .state_offset = 4, .guest_value = 1, .transferred_value = 2, .released_value = 3 }};
const bindings = [_]facts.CanonicalBinding{.{ .name = "payload", .canonical_offset = 0, .payload_size = 4, .frame_offset = 0, .width = 4 }};
const lifecycle = [_]facts.LifecycleAnchor{.{ .name = "life", .required_text = &.{ "acquire", "transfer" }, .ordered_anchors = &.{ "acquire", "transfer" } }};
const markers = [_]facts.MarkerBinding{.{ .name = "descriptor", .expected_value = "test-descriptor" }};

fn contract() producer_contract.ProducerContract {
    return .{
        .descriptor_id = "test-descriptor",
        .source = .{ .module = "source", .import_name = "read", .core_params = &.{}, .core_results = &.{} },
        .sink = .{ .module = "sink", .member = "write", .capacity = 1, .read_import = "read", .write_import = "write", .drop_import = "drop" },
        .payload = .{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } },
        .ownership = .{ .leaves = &.{.{ .path = &path, .resource = "ticket", .handle_offset = 0, .drop_import = "drop", .bit = 0 }}, .parents = &.{} },
        .terminal = .{ .close_action = "close", .abort_action = null, .cancel_action = "cancel", .cleanup_order = &.{.resource} },
    };
}

fn input() state_ir.FrameMapInput {
    return .{ .route_id = "test-route", .descriptor_id = "test-descriptor", .contract = contract(), .frame_facts = .{ .route_id = "test-route", .descriptor_id = "test-descriptor", .frame_size = 128, .frames = &fields, .ownership = &ownership, .bindings = &bindings, .lifecycle = &lifecycle, .markers = &markers } };
}

test "producer canonical frame map accepts a valid direct route" {
    const map = try state_ir.build_frame_map(input());
    try std.testing.expectEqualStrings("test-route", map.route_id);
    try std.testing.expectEqualStrings("test-descriptor", map.descriptor_id);
    try std.testing.expectEqual(@as(u32, 128), map.frame_size);
    try std.testing.expectEqual(@as(u32, 0), map.bindings[0].canonical_offset);
}

test "producer canonical frame map rejects empty identity" {
    var value = input();
    value.route_id = "";
    try std.testing.expectError(error.InvalidIdentity, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects descriptor mismatch" {
    var value = input();
    value.descriptor_id = "other";
    try std.testing.expectError(error.InvalidIdentity, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects frame overlap" {
    var value = input();
    var changed = fields;
    changed[1].offset = 0;
    value.frame_facts.frames = &changed;
    try std.testing.expectError(error.InvalidFrame, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects binding overlap" {
    var value = input();
    const changed = [_]facts.CanonicalBinding{
        .{ .name = "one", .canonical_offset = 0, .payload_size = 8, .frame_offset = 8, .width = 4 },
        .{ .name = "two", .canonical_offset = 2, .payload_size = 8, .frame_offset = 12, .width = 4 },
    };
    value.frame_facts.bindings = &changed;
    try std.testing.expectError(error.BindingOverlap, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects duplicate ownership state" {
    var value = input();
    const changed = [_]facts.OwnershipFact{ ownership[0], .{ .name = "other", .encoding = .scalar, .state_offset = 4, .guest_value = 4, .transferred_value = 5, .released_value = 6 } };
    value.frame_facts.ownership = &changed;
    try std.testing.expectError(error.OwnershipStateOverlap, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects marker value mismatch" {
    var value = input();
    const changed = [_]facts.MarkerBinding{.{ .name = "descriptor", .expected_value = "" }};
    value.frame_facts.markers = &changed;
    try std.testing.expectError(error.InvalidMarker, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects lifecycle anchor drift" {
    var value = input();
    const changed = [_]facts.LifecycleAnchor{.{ .name = "life", .required_text = &.{"acquire"}, .ordered_anchors = &.{"transfer"} }};
    value.frame_facts.lifecycle = &changed;
    try std.testing.expectError(error.InvalidLifecycle, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects batched pointer alias" {
    var value = input();
    const changed = [_]facts.FrameFact{
        .{ .name = "pointer", .offset = 8, .width = 4, .alignment = 4, .role = .list_pointer },
        .{ .name = "length", .offset = 8, .width = 4, .alignment = 4, .role = .list_length },
    };
    value.frame_facts.frames = &changed;
    value.contract.batch_count = 2;
    try std.testing.expectError(error.BatchAlias, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects a 65 asset group" {
    var value = input();
    var many: [65]facts.OwnershipFact = undefined;
    for (&many, 0..) |*entry, index| entry.* = .{ .name = "asset", .encoding = .scalar, .state_offset = @intCast(index * 4), .guest_value = @intCast(index + 1), .transferred_value = @intCast(index + 66), .released_value = @intCast(index + 131) };
    value.frame_facts.ownership = &many;
    try std.testing.expectError(error.UnsupportedBound, state_ir.build_frame_map(value));
}

test "producer canonical frame map rejects zero absence sentinel" {
    var value = input();
    var leaves = [_]producer_contract.OwnershipLeaf{.{ .path = &path, .resource = "ticket", .handle_offset = 0, .drop_import = "drop", .bit = 0, .absence_sentinel = 0 }};
    value.contract.ownership.leaves = &leaves;
    try std.testing.expectError(error.ZeroSentinel, state_ir.build_frame_map(value));
}
