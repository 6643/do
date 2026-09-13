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
const list_values_path = [_][]const u8{"values"};

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

fn lifecycle_map() state_ir.CanonicalFrameMap {
    return state_ir.build_frame_map(input()) catch unreachable;
}

fn list_contract() producer_contract.ProducerContract {
    return .{
        .descriptor_id = "test-descriptor",
        .source = .{ .module = "source", .import_name = "read", .core_params = &.{}, .core_results = &.{} },
        .sink = .{ .module = "sink", .member = "write", .capacity = 1, .read_import = "read", .write_import = "write", .drop_import = "drop" },
        .payload = .{ .list = .{ .pointer_offset = 8, .length_offset = 12, .element_stride = 4, .max_items = 2 } },
        .ownership = contract().ownership,
        .terminal = .{ .close_action = "close", .abort_action = null, .cancel_action = "cancel", .cleanup_order = &.{ .resource, .list } },
        .list_allocations = &.{.{ .path = &list_values_path, .element_core_type = "i32", .pointer_offset = 8, .length_offset = 12, .element_stride = 4, .max_items = 2, .release_import = "release" }},
    };
}

fn list_map() state_ir.CanonicalFrameMap {
    return lifecycle_map();
}

fn build_ir(value: producer_contract.ProducerContract, map: state_ir.CanonicalFrameMap) state_ir.LifecycleStateIR {
    return state_ir.build_lifecycle_ir(value, map) catch unreachable;
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

test "producer canonical frame map rejects an omitted lifecycle anchor" {
    var value = input();
    const changed = [_]facts.LifecycleAnchor{.{
        .name = "life",
        .required_text = &.{ "acquire", "transfer" },
        .ordered_anchors = &.{"acquire"},
    }};
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

test "producer lifecycle state IR accepts direct topology" {
    const ir = build_ir(contract(), lifecycle_map());
    try std.testing.expectEqual(@as(u32, 1), ir.asset_count);
    try std.testing.expectEqual(@as(u32, 1), ir.group_count);
    try std.testing.expectEqual(state_ir.AssetKind.resource, ir.assets[0].kind);
    try std.testing.expectEqual(state_ir.AssetDisposition.transfer_to_host, ir.assets[0].disposition);
    try std.testing.expectEqual(@as(u32, 0), ir.complete_write_barrier[0]);
    try std.testing.expectEqual(@as(u32, 1), ir.transfer_commit[0].asset_count);
    try std.testing.expectEqual(@as(u32, 0), ir.reverse_release[0].asset_index);
    try std.testing.expect(!ir.post_transfer_cancel.rolls_back_host_effects);
}

test "producer lifecycle state IR accepts list backing topology" {
    const value = list_contract();
    const ir = build_ir(value, list_map());
    try std.testing.expectEqual(@as(u32, 2), ir.asset_count);
    try std.testing.expectEqual(state_ir.AssetKind.resource, ir.assets[0].kind);
    try std.testing.expectEqual(state_ir.AssetKind.list_backing, ir.assets[1].kind);
    try std.testing.expectEqual(state_ir.AssetDisposition.release_after_copy, ir.assets[1].disposition);
    try std.testing.expectEqualStrings("values", ir.assets[1].path[0]);
}

test "producer lifecycle state IR models list-only payload without a resource" {
    var value = list_contract();
    value.ownership = .{ .leaves = &.{}, .parents = &.{} };
    const ir = build_ir(value, lifecycle_map());
    try std.testing.expectEqual(@as(u32, 1), ir.asset_count);
    try std.testing.expectEqual(state_ir.AssetKind.list_backing, ir.assets[0].kind);
}

test "producer lifecycle state IR preserves nested child path and release order" {
    const inner = [_][]const u8{"inner"};
    const nested = [_][]const u8{ "inner", "ticket" };
    var value = contract();
    value.ownership = .{ .leaves = &.{.{ .path = &nested, .resource = "ticket", .handle_offset = 0, .drop_import = "drop", .bit = 0 }}, .parents = &.{.{ .path = &inner, .bit = 1 }} };
    const ir = build_ir(value, lifecycle_map());
    try std.testing.expectEqualStrings("inner", ir.assets[0].path[0]);
    try std.testing.expectEqualStrings("ticket", ir.assets[0].path[1]);
    try std.testing.expectEqual(ir.acquire_order[0], ir.reverse_release[0]);
}

test "producer lifecycle state IR isolates batched group ranges" {
    const batched_fields = [_]facts.FrameFact{
        fields[0],
        fields[1],
        .{ .name = "state-2", .offset = 8, .width = 4, .alignment = 4, .role = .ownership_state },
    };
    const batched_ownership = [_]facts.OwnershipFact{ ownership[0], .{ .name = "ticket-2", .encoding = .scalar, .state_offset = 8, .guest_value = 4, .transferred_value = 5, .released_value = 6 } };
    var value = input();
    value.contract.batch_count = 2;
    value.contract.batch_lengths = &.{ 1, 1 };
    value.frame_facts.frames = &batched_fields;
    value.frame_facts.ownership = &batched_ownership;
    const map = try state_ir.build_frame_map(value);
    const ir = try state_ir.build_lifecycle_ir(value.contract, map);
    try std.testing.expectEqual(@as(u32, 2), ir.group_count);
    try std.testing.expectEqual(@as(u32, 2), ir.asset_count);
    try std.testing.expectEqual(@as(u32, 0), ir.groups[0].asset_start);
    try std.testing.expectEqual(@as(u32, 1), ir.groups[1].asset_start);
    try std.testing.expectEqual(@as(u32, 1), ir.transfer_commit[1].asset_start);
}

test "producer lifecycle state IR rejects transfer before complete write" {
    var ir = build_ir(contract(), lifecycle_map());
    ir.barrier_count = 0;
    try std.testing.expectError(error.TransferBeforeCompleteWrite, state_ir.validate_lifecycle_ir(contract(), lifecycle_map(), ir));
}

test "producer lifecycle state IR rejects partial group transfer" {
    var ir = build_ir(list_contract(), list_map());
    ir.transfer_commit[0].asset_count = 1;
    try std.testing.expectError(error.PartialGroupTransfer, state_ir.validate_lifecycle_ir(list_contract(), list_map(), ir));
}

test "producer lifecycle state IR rejects disposition mismatch" {
    var ir = build_ir(contract(), lifecycle_map());
    ir.assets[0].disposition = .release_after_copy;
    try std.testing.expectError(error.InvalidDisposition, state_ir.validate_lifecycle_ir(contract(), lifecycle_map(), ir));
}

test "producer lifecycle state IR rejects reverse release drift" {
    var ir = build_ir(list_contract(), list_map());
    ir.reverse_release[0] = .{ .group_index = 0, .asset_index = 0 };
    try std.testing.expectError(error.InvalidReverseRelease, state_ir.validate_lifecycle_ir(list_contract(), list_map(), ir));
}

test "producer lifecycle state IR rejects duplicate cleanup stage" {
    var ir = build_ir(list_contract(), list_map());
    ir.cleanup_order[1] = .resource;
    try std.testing.expectError(error.DuplicateCleanupStage, state_ir.validate_lifecycle_ir(list_contract(), list_map(), ir));
}

test "producer lifecycle state IR rejects parent before child cleanup" {
    var ir = build_ir(list_contract(), list_map());
    ir.cleanup_order[0] = .list;
    ir.cleanup_order[1] = .resource;
    try std.testing.expectError(error.ParentCleanupBeforeChild, state_ir.validate_lifecycle_ir(list_contract(), list_map(), ir));
}

test "producer lifecycle state IR rejects terminal before cleanup" {
    var ir = build_ir(list_contract(), list_map());
    ir.cleanup_count = 1;
    try std.testing.expectError(error.TerminalBeforeCleanup, state_ir.validate_lifecycle_ir(list_contract(), list_map(), ir));
}

test "producer lifecycle state IR rejects post-transfer rollback" {
    var ir = build_ir(contract(), lifecycle_map());
    ir.post_transfer_cancel.rolls_back_host_effects = true;
    try std.testing.expectError(error.PostTransferRollback, state_ir.validate_lifecycle_ir(contract(), lifecycle_map(), ir));
}

test "producer lifecycle state IR rejects malformed canonical map" {
    var map = lifecycle_map();
    var changed = ownership;
    changed[0].state_offset = 128;
    map.ownership = &changed;
    try std.testing.expectError(error.InvalidAsset, state_ir.build_lifecycle_ir(contract(), map));
}
