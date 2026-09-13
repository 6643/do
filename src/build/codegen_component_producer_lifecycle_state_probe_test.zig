const std = @import("std");
const p3_async_manifest = @import("p3_async_manifest.zig");
const producer_contract = @import("codegen_component_producer_contract.zig");
const mapping_probe = @import("codegen_component_producer_mapping_probe.zig");
const probe = @import("codegen_component_producer_lifecycle_state_probe.zig");

const RouteIdentity = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    member: []const u8,
};

const checked_in_routes = [_]RouteIdentity{
    .{ .route_id = "owned-record-direct", .descriptor_id = "do:g6-2-owned-record-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "owned-record-list", .descriptor_id = "do:g6-2-owned-record-list-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "owned-record-two-list", .descriptor_id = "do:g6-2-owned-record-two-list-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "owned-record-pair", .descriptor_id = "do:g6-2-owned-record-pair-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "owned-record-triple", .descriptor_id = "do:g6-2-owned-record-triple-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "owned-record-nested", .descriptor_id = "do:g6-2-owned-record-nested-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "owned-record-mixed", .descriptor_id = "do:g6-2-owned-record-mixed-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "owned-record-parameterized-pair", .descriptor_id = "do:g6-2-owned-record-pair-parameterized-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "c-min-list", .descriptor_id = "do:g6-2-c-min-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "c-min-dynamic-list", .descriptor_id = "do:g6-2-c-min-dynamic-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "scalar-list", .descriptor_id = "do:g6-2-scalar-list-producer@0.1.0", .member = "consume-via-stream" },
    .{ .route_id = "c-min-batched-list", .descriptor_id = "do:g6-2-batched-list-producer@0.1.0", .member = "consume-via-stream" },
};

const MatrixScenario = enum {
    success,
    pre_transfer_failure,
    post_transfer_cancel,
    batched_mixed,
    repeat,
    incomplete_groups,
};

const ExpectedField = struct { name: []const u8, offset: u32 };
const ExpectedAllocation = struct {
    path: []const []const u8,
    pointer_offset: u32,
    length_offset: u32,
    element_stride: u32,
    max_items: u32,
};

const frame_facts = [_]mapping_probe.FrameFact{
    .{ .name = "result", .offset = 0, .width = 4, .alignment = 4, .role = .result_tag },
};
const ownership_facts = [_]mapping_probe.OwnershipFact{
    .{ .name = "asset", .encoding = .scalar, .state_offset = 4, .guest_value = 1, .transferred_value = 2, .released_value = 3 },
};
const binding_facts = [_]mapping_probe.BindingFact{
    .{ .name = "payload", .canonical_offset = 0, .payload_size = 4, .frame_offset = 0, .width = 4 },
};
const lifecycle_facts = [_]mapping_probe.LifecycleFact{
    .{ .name = "producer", .required_text = &.{ "acquire", "release" }, .ordered_anchors = &.{ "acquire", "release" } },
};
const ticket_path = [_][]const u8{"ticket"};

fn valid_mapping() mapping_probe.TemplateFact {
    return .{
        .route_id = "test-route",
        .template_name = "test.wat",
        .frame_size = 8,
        .frames = &frame_facts,
        .ownership = &ownership_facts,
        .bindings = &binding_facts,
        .lifecycle = &lifecycle_facts,
    };
}

fn valid_contract() producer_contract.ProducerContract {
    return .{
        .descriptor_id = "test-descriptor",
        .source = .{ .module = "source", .import_name = "read", .core_params = &.{}, .core_results = &.{} },
        .sink = .{ .module = "sink", .member = "write", .capacity = 1, .read_import = "read", .write_import = "write", .drop_import = "drop" },
        .payload = .{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } },
        .ownership = .{ .leaves = &.{.{ .path = &ticket_path, .resource = "ticket", .handle_offset = 0, .drop_import = "drop", .bit = 0 }}, .parents = &.{} },
        .terminal = .{ .close_action = "close", .abort_action = null, .cancel_action = "cancel", .cleanup_order = &.{.resource} },
    };
}

fn valid_program() probe.LifecycleProgram {
    return .{ .route_id = "test-route", .contract = valid_contract(), .mapping = valid_mapping(), .events = &.{} };
}

test "producer lifecycle state probe accepts a valid program shell" {
    const report = try probe.validate_program(valid_program());
    try std.testing.expectEqualStrings("test-route", report.route_id);
    try std.testing.expectEqual(@as(u32, 1), report.group_count);
    try std.testing.expectEqual(@as(u32, 1), report.assets_per_group);
    try std.testing.expectEqual(@as(u32, 1), report.asset_count);
}

test "producer lifecycle state probe rejects an empty route" {
    var program = valid_program();
    program.route_id = "";
    try std.testing.expectError(error.InvalidIdentity, probe.validate_program(program));
}

test "producer lifecycle state probe rejects mismatched mapping identity" {
    var program = valid_program();
    program.mapping.route_id = "other-route";
    try std.testing.expectError(error.InvalidIdentity, probe.validate_program(program));
}

test "producer lifecycle state probe rejects invalid contract" {
    var program = valid_program();
    program.contract.descriptor_id = "";
    try std.testing.expectError(error.InvalidContract, probe.validate_program(program));
}

const many_groups = [_]mapping_probe.OwnershipFact{.{
    .name = "asset",
    .encoding = .scalar,
    .state_offset = 4,
    .guest_value = 1,
    .transferred_value = 2,
    .released_value = 3,
}} ** 65;

test "producer lifecycle state probe rejects more than 64 groups" {
    var program = valid_program();
    program.contract.batch_count = 65;
    program.mapping.ownership = &many_groups;
    try std.testing.expectError(error.UnsupportedProbeBound, probe.validate_program(program));
}

const many_paths = blk: {
    @setEvalBranchQuota(100000);
    var paths: [65][]const []const u8 = undefined;
    for (0..65) |index| {
        const name = std.fmt.comptimePrint("asset-{d}", .{index});
        paths[index] = &.{name};
    }
    break :blk paths;
};

const many_allocations = blk: {
    var allocations: [65]producer_contract.ListAllocation = undefined;
    for (0..65) |index| {
        allocations[index] = .{
            .path = many_paths[index],
            .element_core_type = "i32",
            .pointer_offset = @intCast(8 + index * 8),
            .length_offset = @intCast(4 + index * 8),
            .element_stride = 4,
            .max_items = 1,
            .release_import = "release",
        };
    }
    break :blk allocations;
};

test "producer lifecycle state probe rejects more than 64 assets per group" {
    var program = valid_program();
    program.contract.list_allocations = &many_allocations;
    try std.testing.expectError(error.UnsupportedProbeBound, probe.validate_program(program));
}

test "producer lifecycle state probe keeps distinct payload list backing identities" {
    const list_path = [_][]const u8{"values"};
    const allocation = producer_contract.ListAllocation{
        .path = &list_path,
        .element_core_type = "i32",
        .pointer_offset = 8,
        .length_offset = 12,
        .element_stride = 8,
        .max_items = 2,
        .release_import = "release",
    };
    var allocations = [_]producer_contract.ListAllocation{allocation};
    var program = valid_program();
    program.contract.payload = .{ .list = .{
        .pointer_offset = 8,
        .length_offset = 12,
        .element_stride = 4,
        .max_items = 1,
    } };
    program.contract.list_allocations = &allocations;
    const report = try probe.validate_program(program);
    try std.testing.expectEqual(@as(u32, 3), report.assets_per_group);
}

test "producer lifecycle state probe derives a direct resource asset" {
    const model = try probe.derive_model_for_test(valid_program());
    try std.testing.expectEqual(@as(u32, 1), model.asset_count);
    try std.testing.expectEqual(probe.AssetKind.resource, model.assets[0].kind);
    try std.testing.expectEqual(probe.Disposition.transfer_to_host, model.assets[0].disposition);
    try std.testing.expectEqualStrings("ticket", model.assets[0].path[0]);
}

test "producer lifecycle state probe derives list backing after resource" {
    const path = [_][]const u8{"values"};
    const allocation = producer_contract.ListAllocation{
        .path = &path,
        .element_core_type = "i32",
        .pointer_offset = 8,
        .length_offset = 12,
        .element_stride = 4,
        .max_items = 2,
        .release_import = "release",
    };
    var allocations = [_]producer_contract.ListAllocation{allocation};
    var program = valid_program();
    program.contract.list_allocations = &allocations;
    const model = try probe.derive_model_for_test(program);
    try std.testing.expectEqual(@as(u32, 2), model.asset_count);
    try std.testing.expectEqual(probe.AssetKind.resource, model.assets[0].kind);
    try std.testing.expectEqual(probe.AssetKind.list_backing, model.assets[1].kind);
    try std.testing.expectEqual(probe.Disposition.release_after_copy, model.assets[1].disposition);
    try std.testing.expectEqualStrings("values", model.assets[1].path[0]);
}

test "producer lifecycle state probe retains nested ownership path" {
    const inner = [_][]const u8{ "inner", "ticket" };
    var contract = valid_contract();
    var leaves = [_]producer_contract.OwnershipLeaf{contract.ownership.leaves[0]};
    leaves[0].path = &inner;
    contract.ownership.leaves = &leaves;
    var program = valid_program();
    program.contract = contract;
    const model = try probe.derive_model_for_test(program);
    try std.testing.expectEqual(@as(usize, 2), model.assets[0].path.len);
    try std.testing.expectEqualStrings("inner", model.assets[0].path[0]);
    try std.testing.expectEqualStrings("ticket", model.assets[0].path[1]);
}

test "producer lifecycle state probe derives scalar list backing without ownership leaves" {
    var contract = valid_contract();
    contract.payload = .{ .list = .{ .pointer_offset = 8, .length_offset = 12, .element_stride = 4, .max_items = 2 } };
    contract.ownership = .{ .leaves = &.{}, .parents = &.{} };
    var program = valid_program();
    program.contract = contract;
    const model = try probe.derive_model_for_test(program);
    try std.testing.expectEqual(@as(u32, 1), model.asset_count);
    try std.testing.expectEqual(probe.AssetKind.list_backing, model.assets[0].kind);
}

test "producer lifecycle state probe isolates batched asset ranges" {
    const groups = [_]mapping_probe.OwnershipFact{ ownership_facts[0], ownership_facts[0] };
    var mapping = valid_mapping();
    mapping.ownership = &groups;
    var contract = valid_contract();
    contract.batch_count = 2;
    var program = valid_program();
    program.mapping = mapping;
    program.contract = contract;
    const model = try probe.derive_model_for_test(program);
    try std.testing.expectEqual(@as(u32, 2), model.group_count);
    try std.testing.expectEqual(@as(u32, 2), model.asset_count);
    try std.testing.expectEqual(@as(u8, 0), try probe.asset_bit(model, .{ .group_index = 0, .asset_index = 0 }));
    try std.testing.expectEqual(@as(u8, 1), try probe.asset_bit(model, .{ .group_index = 1, .asset_index = 0 }));
}

test "producer lifecycle state probe rejects a synthetic 65 asset contract" {
    var program = valid_program();
    program.contract.list_allocations = &many_allocations;
    try std.testing.expectError(error.UnsupportedProbeBound, probe.derive_model_for_test(program));
}

test "producer lifecycle state probe guards asset ids" {
    const model = try probe.derive_model_for_test(valid_program());
    try std.testing.expectError(error.InvalidAsset, probe.asset_bit(model, .{ .group_index = 1, .asset_index = 0 }));
    try std.testing.expectError(error.InvalidAsset, probe.asset_bit(model, .{ .group_index = 0, .asset_index = 1 }));
}

const pair_left_path = [_][]const u8{"left"};
const pair_right_path = [_][]const u8{"right"};
const pair_leaves = [_]producer_contract.OwnershipLeaf{
    .{ .path = &pair_left_path, .resource = "left", .handle_offset = 0, .drop_import = "drop", .bit = 0 },
    .{ .path = &pair_right_path, .resource = "right", .handle_offset = 4, .drop_import = "drop", .bit = 1 },
};
const list_allocation = producer_contract.ListAllocation{
    .path = &list_values_path,
    .element_core_type = "i32",
    .pointer_offset = 8,
    .length_offset = 12,
    .element_stride = 4,
    .max_items = 2,
    .release_import = "release",
};

fn pair_program(events: []const probe.LifecycleEvent) probe.LifecycleProgram {
    var contract = valid_contract();
    contract.ownership.leaves = &pair_leaves;
    return .{ .route_id = "test-route", .contract = contract, .mapping = valid_mapping(), .events = events };
}

const list_values_path = [_][]const u8{"values"};

fn list_program(events: []const probe.LifecycleEvent) probe.LifecycleProgram {
    var contract = valid_contract();
    contract.payload = .{ .list = .{ .pointer_offset = 8, .length_offset = 12, .element_stride = 4, .max_items = 2 } };
    contract.list_allocations = &.{list_allocation};
    contract.terminal.cleanup_order = &.{ .resource, .list };
    return .{ .route_id = "test-route", .contract = contract, .mapping = valid_mapping(), .events = events };
}

test "producer lifecycle state probe transition accepts acquire write transfer cleanup terminal" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .acquire = .{ .group_index = 0, .asset_index = 1 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .cleanup_stage = .resource },
        .{ .cleanup_stage = .list },
        .{ .terminal = {} },
    };
    const observation = try probe.run(list_program(&events));
    try std.testing.expectEqual(@as(u32, 2), observation.acquired_count);
    try std.testing.expectEqual(@as(u32, 1), observation.transferred_count);
    try std.testing.expectEqual(@as(u32, 1), observation.released_count);
    try std.testing.expectEqual(@as(u32, 2), observation.cleanup_stage_count);
    try std.testing.expectEqual(probe.TerminalState.completed, observation.terminal_state);
}

test "producer lifecycle state probe transition rejects transfer before write" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .transfer_commit = 0 },
    };
    try std.testing.expectError(error.TransferBeforeWrite, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects incomplete pair write" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
    };
    try std.testing.expectError(error.WriteIncomplete, probe.run(pair_program(&events)));
}

test "producer lifecycle state probe transition rejects duplicate acquire" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
    };
    try std.testing.expectError(error.DuplicateAcquire, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects release order swap" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .acquire = .{ .group_index = 0, .asset_index = 1 } },
        .{ .release = .{ .group_index = 0, .asset_index = 0 } },
    };
    try std.testing.expectError(error.InvalidReleaseOrder, probe.run(pair_program(&events)));
}

test "producer lifecycle state probe transition rejects guest release after transfer" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .release = .{ .group_index = 0, .asset_index = 0 } },
    };
    try std.testing.expectError(error.GuestReleaseAfterTransfer, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects duplicate release" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .release = .{ .group_index = 0, .asset_index = 0 } },
        .{ .release = .{ .group_index = 0, .asset_index = 0 } },
    };
    try std.testing.expectError(error.DuplicateRelease, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects duplicate transfer" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .transfer_commit = 0 },
    };
    try std.testing.expectError(error.DuplicateTransfer, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition counts pre-transfer releases" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .acquire = .{ .group_index = 0, .asset_index = 1 } },
        .{ .release = .{ .group_index = 0, .asset_index = 1 } },
        .{ .release = .{ .group_index = 0, .asset_index = 0 } },
        .{ .cleanup_stage = .resource },
        .{ .terminal = {} },
    };
    const observation = try probe.run(pair_program(&events));
    try std.testing.expectEqual(@as(u32, 0), observation.transferred_count);
    try std.testing.expectEqual(@as(u32, 2), observation.released_count);
}

test "producer lifecycle state probe transition preserves transfer across cancel" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .cancel = {} },
        .{ .cleanup_stage = .resource },
        .{ .terminal = {} },
    };
    const observation = try probe.run(valid_program_with_events(&events));
    try std.testing.expectEqual(@as(u32, 1), observation.transferred_count);
    try std.testing.expectEqual(@as(u32, 0), observation.released_count);
    try std.testing.expectEqual(probe.TerminalState.completed, observation.terminal_state);
}

test "producer lifecycle state probe transition rejects transfer after cancel" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .cancel = {} },
        .{ .transfer_commit = 0 },
    };
    try std.testing.expectError(error.TransferAfterCancel, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects acquire write after cancel" {
    const acquire_events = [_]probe.LifecycleEvent{ .{ .cancel = {} }, .{ .acquire = .{ .group_index = 0, .asset_index = 0 } } };
    try std.testing.expectError(error.AcquireAfterCancel, probe.run(valid_program_with_events(&acquire_events)));

    const write_events = [_]probe.LifecycleEvent{ .{ .cancel = {} }, .{ .write_complete = 0 } };
    try std.testing.expectError(error.WriteAfterCancel, probe.run(valid_program_with_events(&write_events)));
}

test "producer lifecycle state probe transition rejects release of absent asset" {
    const events = [_]probe.LifecycleEvent{.{ .release = .{ .group_index = 0, .asset_index = 0 } }};
    try std.testing.expectError(error.AssetNotOwned, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects duplicate and late cancel" {
    const duplicate_events = [_]probe.LifecycleEvent{ .{ .cancel = {} }, .{ .cancel = {} } };
    try std.testing.expectError(error.DuplicateCancel, probe.run(valid_program_with_events(&duplicate_events)));

    const late_events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .cleanup_stage = .resource },
        .{ .terminal = {} },
        .{ .cancel = {} },
    };
    try std.testing.expectError(error.CancelAfterTerminal, probe.run(valid_program_with_events(&late_events)));
}

test "producer lifecycle state probe transition rejects cleanup before asset finalization" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .cleanup_stage = .resource },
    };
    try std.testing.expectError(error.CleanupBeforeAssets, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects cleanup before acquisition" {
    const events = [_]probe.LifecycleEvent{
        .{ .cleanup_stage = .resource },
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .terminal = {} },
    };
    try std.testing.expectError(error.CleanupBeforeAssets, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects cleanup order drift" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .acquire = .{ .group_index = 0, .asset_index = 1 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .cleanup_stage = .list },
    };
    try std.testing.expectError(error.CleanupStageMismatch, probe.run(list_program(&events)));
}

test "producer lifecycle state probe transition rejects terminal with guest assets" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .terminal = {} },
    };
    try std.testing.expectError(error.TerminalBeforeAssets, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects cleanup after terminal" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .cleanup_stage = .resource },
        .{ .terminal = {} },
        .{ .cleanup_stage = .resource },
    };
    try std.testing.expectError(error.CleanupAfterTerminal, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects early and duplicate terminal" {
    const early_events = [_]probe.LifecycleEvent{.{ .terminal = {} }};
    try std.testing.expectError(error.TerminalBeforeCleanup, probe.run(valid_program_with_events(&early_events)));

    const duplicate_events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .cleanup_stage = .resource },
        .{ .terminal = {} },
        .{ .terminal = {} },
    };
    try std.testing.expectError(error.DuplicateTerminal, probe.run(valid_program_with_events(&duplicate_events)));
}

test "producer lifecycle state probe transition rejects out of range asset" {
    const events = [_]probe.LifecycleEvent{.{ .acquire = .{ .group_index = 1, .asset_index = 0 } }};
    try std.testing.expectError(error.InvalidAsset, probe.run(valid_program_with_events(&events)));
}

test "producer lifecycle state probe transition rejects missing terminal" {
    const events = [_]probe.LifecycleEvent{
        .{ .acquire = .{ .group_index = 0, .asset_index = 0 } },
        .{ .write_complete = 0 },
        .{ .transfer_commit = 0 },
        .{ .cleanup_stage = .resource },
    };
    try std.testing.expectError(error.TraceIncomplete, probe.run(valid_program_with_events(&events)));
}

fn valid_program_with_events(events: []const probe.LifecycleEvent) probe.LifecycleProgram {
    return .{ .route_id = "test-route", .contract = valid_contract(), .mapping = valid_mapping(), .events = events };
}

test "producer lifecycle state probe covers twelve checked-in routes" {
    try run_checked_in_matrix(.success);
}

test "producer lifecycle state probe covers transfer-before-failure cleanup" {
    try run_checked_in_matrix(.pre_transfer_failure);
}

test "producer lifecycle state probe covers transfer-after-cancel" {
    try run_checked_in_matrix(.post_transfer_cancel);
}

test "producer lifecycle state probe isolates batched groups" {
    try run_checked_in_matrix(.batched_mixed);
}

test "producer lifecycle state probe doubles observations for repeat" {
    try run_checked_in_matrix(.repeat);
}

test "producer lifecycle state probe rejects incomplete pair and triple groups" {
    try run_checked_in_matrix(.incomplete_groups);
}

fn run_checked_in_matrix(scenario: MatrixScenario) !void {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var matched: usize = 0;
    for (checked_in_routes) |identity| {
        const descriptor = registry.find(identity.descriptor_id, identity.member) orelse
            return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(identity.member, descriptor.member);

        const mapping = mapping_probe.fact_for_route(identity.route_id) orelse
            return error.TestUnexpectedResult;
        const contract = try producer_contract.producer_contract_from_descriptor(descriptor);
        try std.testing.expectEqualStrings(identity.descriptor_id, contract.descriptor_id);
        try std.testing.expectEqualStrings(identity.member, contract.sink.member);

        var empty_events: [1]probe.LifecycleEvent = undefined;
        const shell = probe.LifecycleProgram{
            .route_id = identity.route_id,
            .contract = contract,
            .mapping = mapping.*,
            .events = empty_events[0..0],
        };
        const report = try probe.validate_program(shell);
        try std.testing.expectEqualStrings(identity.route_id, report.route_id);
        try assert_checked_in_route_facts(identity.route_id, contract, mapping.*, report);

        switch (scenario) {
            .success => try assert_success_trace(report, contract, mapping.*),
            .pre_transfer_failure => try assert_pre_transfer_failure(report, contract, mapping.*),
            .post_transfer_cancel => try assert_post_transfer_cancel(report, contract, mapping.*),
            .batched_mixed => {
                if (!std.mem.eql(u8, identity.route_id, "c-min-batched-list")) continue;
                try assert_batched_mixed(report, contract, mapping.*);
                matched += 1;
            },
            .repeat => try assert_repeat(report, contract, mapping.*),
            .incomplete_groups => {
                if (!std.mem.eql(u8, identity.route_id, "owned-record-pair") and
                    !std.mem.eql(u8, identity.route_id, "owned-record-triple")) continue;
                try assert_incomplete_group(report, contract, mapping.*);
                matched += 1;
            },
        }
        if (scenario != .batched_mixed and scenario != .incomplete_groups) matched += 1;
    }

    const expected = switch (scenario) {
        .batched_mixed => 1,
        .incomplete_groups => 2,
        else => checked_in_routes.len,
    };
    try std.testing.expectEqual(expected, matched);
}

fn append_event(buffer: *[256]probe.LifecycleEvent, length: *usize, event: probe.LifecycleEvent) !void {
    if (length.* >= buffer.len) return error.TestUnexpectedResult;
    buffer[length.*] = event;
    length.* += 1;
}

fn append_acquire_all(
    buffer: *[256]probe.LifecycleEvent,
    length: *usize,
    report: probe.ProgramReport,
) !void {
    for (0..@as(usize, @intCast(report.group_count))) |group_index| {
        for (0..@as(usize, @intCast(report.assets_per_group))) |asset_index| {
            try append_event(buffer, length, .{ .acquire = .{
                .group_index = @intCast(group_index),
                .asset_index = @intCast(asset_index),
            } });
        }
    }
}

fn append_release_all_reverse(
    buffer: *[256]probe.LifecycleEvent,
    length: *usize,
    report: probe.ProgramReport,
) !void {
    var group_index = report.group_count;
    while (group_index != 0) {
        group_index -= 1;
        var asset_index = report.assets_per_group;
        while (asset_index != 0) {
            asset_index -= 1;
            try append_event(buffer, length, .{ .release = .{
                .group_index = group_index,
                .asset_index = asset_index,
            } });
        }
    }
}

fn append_complete_and_transfer_all(
    buffer: *[256]probe.LifecycleEvent,
    length: *usize,
    report: probe.ProgramReport,
) !void {
    for (0..@as(usize, @intCast(report.group_count))) |group_index| {
        try append_event(buffer, length, .{ .write_complete = @intCast(group_index) });
        try append_event(buffer, length, .{ .transfer_commit = @intCast(group_index) });
    }
}

fn append_cleanup_and_terminal(
    buffer: *[256]probe.LifecycleEvent,
    length: *usize,
    contract: producer_contract.ProducerContract,
) !void {
    for (contract.terminal.cleanup_order) |stage| {
        try append_event(buffer, length, .{ .cleanup_stage = stage });
    }
    try append_event(buffer, length, .{ .terminal = {} });
}

fn success_trace(
    buffer: *[256]probe.LifecycleEvent,
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
) ![]const probe.LifecycleEvent {
    var length: usize = 0;
    try append_acquire_all(buffer, &length, report);
    try append_complete_and_transfer_all(buffer, &length, report);
    try append_cleanup_and_terminal(buffer, &length, contract);
    return buffer[0..length];
}

fn pre_transfer_failure_trace(
    buffer: *[256]probe.LifecycleEvent,
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
) ![]const probe.LifecycleEvent {
    var length: usize = 0;
    try append_acquire_all(buffer, &length, report);
    try append_release_all_reverse(buffer, &length, report);
    try append_cleanup_and_terminal(buffer, &length, contract);
    return buffer[0..length];
}

fn post_transfer_cancel_trace(
    buffer: *[256]probe.LifecycleEvent,
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
) ![]const probe.LifecycleEvent {
    var length: usize = 0;
    try append_acquire_all(buffer, &length, report);
    try append_complete_and_transfer_all(buffer, &length, report);
    try append_event(buffer, &length, .{ .cancel = {} });
    try append_cleanup_and_terminal(buffer, &length, contract);
    return buffer[0..length];
}

fn batched_mixed_trace(
    buffer: *[256]probe.LifecycleEvent,
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
) ![]const probe.LifecycleEvent {
    if (report.group_count != 2) return error.TestUnexpectedResult;
    var length: usize = 0;
    for (0..@as(usize, @intCast(report.assets_per_group))) |asset_index| {
        try append_event(buffer, &length, .{ .acquire = .{ .group_index = 0, .asset_index = @intCast(asset_index) } });
    }
    try append_event(buffer, &length, .{ .write_complete = 0 });
    try append_event(buffer, &length, .{ .transfer_commit = 0 });
    for (0..@as(usize, @intCast(report.assets_per_group))) |asset_index| {
        try append_event(buffer, &length, .{ .acquire = .{ .group_index = 1, .asset_index = @intCast(asset_index) } });
    }
    var asset_index = report.assets_per_group;
    while (asset_index != 0) {
        asset_index -= 1;
        try append_event(buffer, &length, .{ .release = .{ .group_index = 1, .asset_index = asset_index } });
    }
    try append_cleanup_and_terminal(buffer, &length, contract);
    return buffer[0..length];
}

fn lifecycle_program(
    route_id: []const u8,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
    events: []const probe.LifecycleEvent,
) probe.LifecycleProgram {
    return .{ .route_id = route_id, .contract = contract, .mapping = mapping, .events = events };
}

fn disposition_counts(model: probe.Model) struct { resources: u32, list_backing: u32 } {
    var resources: u32 = 0;
    var list_backing: u32 = 0;
    for (model.assets[0..@as(usize, @intCast(model.asset_count))]) |asset| {
        switch (asset.disposition) {
            .transfer_to_host => resources += 1,
            .release_after_copy => list_backing += 1,
        }
    }
    return .{ .resources = resources, .list_backing = list_backing };
}

fn assert_success_trace(
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
) !void {
    var events: [256]probe.LifecycleEvent = undefined;
    const trace = try success_trace(&events, report, contract);
    const observation = try probe.run(lifecycle_program(report.route_id, contract, mapping, trace));
    const model = try probe.derive_model_for_test(lifecycle_program(report.route_id, contract, mapping, &.{}));
    const counts = disposition_counts(model);
    try std.testing.expectEqual(probe.TerminalState.completed, observation.terminal_state);
    try std.testing.expectEqual(report.asset_count, observation.acquired_count);
    try std.testing.expectEqual(counts.resources, observation.transferred_count);
    try std.testing.expectEqual(counts.list_backing, observation.released_count);
    try std.testing.expectEqual(@as(u32, @intCast(contract.terminal.cleanup_order.len)), observation.cleanup_stage_count);
}

fn assert_pre_transfer_failure(
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
) !void {
    var events: [256]probe.LifecycleEvent = undefined;
    const trace = try pre_transfer_failure_trace(&events, report, contract);
    const observation = try probe.run(lifecycle_program(report.route_id, contract, mapping, trace));
    try std.testing.expectEqual(@as(u32, 0), observation.transferred_count);
    try std.testing.expectEqual(report.asset_count, observation.released_count);
    try std.testing.expectEqual(report.asset_count, observation.acquired_count);
    try std.testing.expectEqual(probe.TerminalState.completed, observation.terminal_state);
}

fn assert_post_transfer_cancel(
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
) !void {
    var events: [256]probe.LifecycleEvent = undefined;
    const trace = try post_transfer_cancel_trace(&events, report, contract);
    const observation = try probe.run(lifecycle_program(report.route_id, contract, mapping, trace));
    const model = try probe.derive_model_for_test(lifecycle_program(report.route_id, contract, mapping, &.{}));
    const counts = disposition_counts(model);
    if (std.mem.eql(u8, report.route_id, "scalar-list")) {
        try std.testing.expectEqual(@as(usize, 0), contract.ownership.leaves.len);
    } else {
        try assert_resource_asset_zero(report.route_id, contract);
        try assert_post_transfer_cancel_rejects_guest_release(report, contract, mapping);
    }
    try std.testing.expectEqual(counts.resources, observation.transferred_count);
    try std.testing.expectEqual(counts.list_backing, observation.released_count);
    try std.testing.expectEqual(probe.TerminalState.completed, observation.terminal_state);
}

fn assert_resource_asset_zero(route_id: []const u8, contract: producer_contract.ProducerContract) !void {
    const expected_path: []const []const u8 = if (std.mem.eql(u8, route_id, "owned-record-nested"))
        &.{ "inner", "ticket" }
    else if (std.mem.eql(u8, route_id, "c-min-list") or
        std.mem.eql(u8, route_id, "c-min-dynamic-list") or
        std.mem.eql(u8, route_id, "c-min-batched-list"))
        &.{ "list", "ticket" }
    else if (std.mem.eql(u8, route_id, "owned-record-pair"))
        &.{"left"}
    else if (std.mem.eql(u8, route_id, "owned-record-triple"))
        &.{"left"}
    else if (std.mem.eql(u8, route_id, "owned-record-parameterized-pair"))
        &.{"left"}
    else if (std.mem.eql(u8, route_id, "owned-record-direct") or
        std.mem.eql(u8, route_id, "owned-record-list") or
        std.mem.eql(u8, route_id, "owned-record-two-list") or
        std.mem.eql(u8, route_id, "owned-record-mixed"))
        &.{"ticket"}
    else
        return error.TestUnexpectedResult;

    try std.testing.expect(contract.ownership.leaves.len != 0);
    const asset_zero = contract.ownership.leaves[0];
    try expect_path(asset_zero.path, expected_path);
    try std.testing.expectEqualStrings("ticket", asset_zero.resource);
    try std.testing.expectEqualStrings("[resource-drop]ticket", asset_zero.drop_import);
}

fn assert_post_transfer_cancel_rejects_guest_release(
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
) !void {
    var events: [256]probe.LifecycleEvent = undefined;
    var length: usize = 0;
    try append_acquire_all(&events, &length, report);
    try append_complete_and_transfer_all(&events, &length, report);
    try append_event(&events, &length, .{ .cancel = {} });
    try append_event(&events, &length, .{ .release = .{ .group_index = 0, .asset_index = 0 } });
    try append_cleanup_and_terminal(&events, &length, contract);
    try std.testing.expectError(
        error.GuestReleaseAfterTransfer,
        probe.run(lifecycle_program(report.route_id, contract, mapping, events[0..length])),
    );
}

fn assert_checked_in_route_facts(
    route_id: []const u8,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
    report: probe.ProgramReport,
) !void {
    const expected_cleanup = [_]producer_contract.CleanupStage{ .resource, .list, .stream, .future, .subtask, .waitable, .frame };
    try std.testing.expectEqualSlices(producer_contract.CleanupStage, &expected_cleanup, contract.terminal.cleanup_order);

    if (std.mem.eql(u8, route_id, "owned-record-direct")) {
        try expect_report(report, 1, 1, 1);
        try expect_mapping(mapping, "resource-or-list", .scalar, 1, 2, 3, &.{"ticket"});
        try expect_record(contract, "resource-entry", 4, &.{.{ .name = "ticket", .offset = 0 }});
        try expect_owned_paths(contract, &.{&.{"ticket"}}, &.{});
    } else if (std.mem.eql(u8, route_id, "owned-record-list")) {
        try expect_report(report, 1, 2, 2);
        try expect_mapping(mapping, "resource-or-list", .scalar, 1, 2, 3, &.{"record-entry"});
        try expect_record(contract, "list-entry", 12, &.{ .{ .name = "values", .offset = 0 }, .{ .name = "ticket", .offset = 8 } });
        try expect_owned_paths(contract, &.{&.{"ticket"}}, &.{});
        try expect_list_allocations(contract, &.{.{ .path = &.{"values"}, .pointer_offset = 0, .length_offset = 4, .element_stride = 4, .max_items = 3 }});
    } else if (std.mem.eql(u8, route_id, "owned-record-two-list")) {
        try expect_report(report, 1, 3, 3);
        try expect_mapping(mapping, "resource-or-list", .scalar, 1, 2, 3, &.{"two-list-entry"});
        try expect_record(contract, "two-list-entry", 20, &.{ .{ .name = "first", .offset = 0 }, .{ .name = "second", .offset = 8 }, .{ .name = "ticket", .offset = 16 } });
        try expect_owned_paths(contract, &.{&.{"ticket"}}, &.{});
        try expect_list_allocations(contract, &.{ .{ .path = &.{"first"}, .pointer_offset = 0, .length_offset = 4, .element_stride = 4, .max_items = 3 }, .{ .path = &.{"second"}, .pointer_offset = 8, .length_offset = 12, .element_stride = 4, .max_items = 3 } });
    } else if (std.mem.eql(u8, route_id, "owned-record-pair")) {
        try expect_report(report, 1, 2, 2);
        try expect_mapping(mapping, "resource-pair", .mask, 3, 4, 0, &.{ "left", "right" });
        try expect_record(contract, "resource-pair", 8, &.{ .{ .name = "left", .offset = 0 }, .{ .name = "right", .offset = 4 } });
        try expect_owned_paths(contract, &.{ &.{"left"}, &.{"right"} }, &.{});
    } else if (std.mem.eql(u8, route_id, "owned-record-triple")) {
        try expect_report(report, 1, 3, 3);
        try expect_mapping(mapping, "resource-triple", .mask, 7, 8, 0, &.{ "left", "middle", "right" });
        try expect_record(contract, "resource-triple", 12, &.{ .{ .name = "left", .offset = 0 }, .{ .name = "middle", .offset = 4 }, .{ .name = "right", .offset = 8 } });
        try expect_owned_paths(contract, &.{ &.{"left"}, &.{"middle"}, &.{"right"} }, &.{});
    } else if (std.mem.eql(u8, route_id, "owned-record-nested")) {
        try expect_report(report, 1, 1, 1);
        try expect_mapping(mapping, "nested-inner-ticket", .mask, 1, 2, 0, &.{"ticket"});
        try expect_record(contract, "outer", 4, &.{.{ .name = "ticket", .offset = 0 }});
        try expect_owned_paths(contract, &.{&.{ "inner", "ticket" }}, &.{&.{"inner"}});
        try std.testing.expectEqual(@as(u8, 0), contract.ownership.leaves[0].bit);
        try std.testing.expectEqual(@as(u8, 1), contract.ownership.parents[0].bit);
    } else if (std.mem.eql(u8, route_id, "owned-record-mixed")) {
        try expect_report(report, 1, 1, 1);
        try expect_mapping(mapping, "resource-or-list", .scalar, 1, 2, 3, &.{ "left", "right" });
        try expect_record(contract, "mixed-entry", 8, &.{ .{ .name = "code", .offset = 0 }, .{ .name = "ticket", .offset = 4 } });
        try expect_owned_paths(contract, &.{&.{"ticket"}}, &.{});
        const record = record_layout(contract);
        try std.testing.expectEqual(p3_async_manifest.RecordOwnership.none, record.source_fields[0].ownership);
        try std.testing.expect(record.source_fields[0].resource == null);
        try std.testing.expectEqual(p3_async_manifest.RecordOwnership.own, record.source_fields[1].ownership);
    } else if (std.mem.eql(u8, route_id, "owned-record-parameterized-pair")) {
        try expect_report(report, 1, 2, 2);
        try expect_mapping(mapping, "resource-pair", .mask, 3, 4, 0, &.{ "left", "right" });
        try expect_record(contract, "resource-pair", 8, &.{ .{ .name = "left", .offset = 0 }, .{ .name = "right", .offset = 4 } });
        try expect_owned_paths(contract, &.{ &.{"left"}, &.{"right"} }, &.{});
        try std.testing.expectEqualStrings("u32", contract.runtime_mode_param.?);
        try std.testing.expectEqualStrings("u32", contract.left_seed_param.?);
        try std.testing.expectEqualStrings("u32", contract.right_seed_param.?);
        try std.testing.expectEqual(@as(usize, 3), contract.producer_core_params.len);
        try std.testing.expectEqual(@as(usize, 1), contract.producer_core_results.len);
    } else if (std.mem.eql(u8, route_id, "c-min-list")) {
        try expect_report(report, 1, 2, 2);
        try expect_mapping(mapping, "resource-or-list", .scalar, 1, 2, 3, &.{ "list-pointer", "list-length" });
        try expect_list_payload(contract, 64, 68, 4, 3);
        try expect_owned_paths(contract, &.{&.{ "list", "ticket" }}, &.{&.{"list"}});
        try std.testing.expectEqualStrings("result-area", contract.terminal.close_action);
    } else if (std.mem.eql(u8, route_id, "c-min-dynamic-list")) {
        try expect_report(report, 1, 2, 2);
        try expect_mapping(mapping, "resource-or-list", .scalar, 1, 2, 3, &.{ "list-pointer", "list-length" });
        try expect_list_payload(contract, 64, 68, 4, 3);
        try expect_owned_paths(contract, &.{&.{ "list", "ticket" }}, &.{&.{"list"}});
        try std.testing.expectEqualStrings("u32", contract.runtime_count_param.?);
        try std.testing.expectEqual(@as(u32, 3), contract.runtime_max.?);
    } else if (std.mem.eql(u8, route_id, "scalar-list")) {
        try expect_report(report, 1, 1, 1);
        try expect_mapping(mapping, "resource-or-list", .scalar, 1, 2, 3, &.{ "list-pointer", "list-length" });
        try expect_list_payload(contract, 64, 68, 4, 3);
        try std.testing.expectEqual(@as(usize, 0), contract.ownership.leaves.len);
        try std.testing.expectEqual(@as(usize, 0), contract.ownership.parents.len);
        try std.testing.expectEqualStrings("u32", contract.runtime_count_param.?);
        try std.testing.expectEqual(@as(u32, 3), contract.runtime_max.?);
    } else if (std.mem.eql(u8, route_id, "c-min-batched-list")) {
        try expect_report(report, 2, 2, 4);
        try expect_mapping(mapping, "batch-0", .batched_scalar, 1, 2, 3, &.{ "batch-0-pointer", "batch-0-length", "batch-1-pointer", "batch-1-length" });
        try std.testing.expectEqual(@as(usize, 2), mapping.ownership.len);
        try std.testing.expectEqualStrings("batch-1", mapping.ownership[1].name);
        try expect_list_payload(contract, 64, 68, 4, 2);
        try expect_owned_paths(contract, &.{&.{ "list", "ticket" }}, &.{&.{"list"}});
        try std.testing.expectEqual(@as(u32, 2), contract.batch_count.?);
        try std.testing.expectEqualSlices(u32, &.{ 2, 1 }, contract.batch_lengths);
        try std.testing.expectEqual(mapping_probe.OwnershipEncoding.batched_scalar, mapping.ownership[1].encoding);
        try std.testing.expectEqual(@as(u32, 1), mapping.ownership[1].guest_value);
        try std.testing.expectEqual(@as(u32, 2), mapping.ownership[1].transferred_value);
        try std.testing.expectEqual(@as(u32, 3), mapping.ownership[1].released_value);
    } else return error.TestUnexpectedResult;
}

fn expect_report(report: probe.ProgramReport, groups: u32, assets_per_group: u32, assets: u32) !void {
    try std.testing.expectEqual(groups, report.group_count);
    try std.testing.expectEqual(assets_per_group, report.assets_per_group);
    try std.testing.expectEqual(assets, report.asset_count);
}

fn expect_mapping(
    mapping: mapping_probe.TemplateFact,
    ownership_name: []const u8,
    encoding: mapping_probe.OwnershipEncoding,
    guest_value: u32,
    transferred_value: u32,
    released_value: u32,
    binding_names: []const []const u8,
) !void {
    try std.testing.expectEqual(@as(usize, binding_names.len), mapping.bindings.len);
    for (binding_names, 0..) |name, index| try std.testing.expectEqualStrings(name, mapping.bindings[index].name);
    try std.testing.expect(mapping.ownership.len != 0);
    try std.testing.expectEqualStrings(ownership_name, mapping.ownership[0].name);
    try std.testing.expectEqual(encoding, mapping.ownership[0].encoding);
    try std.testing.expectEqual(guest_value, mapping.ownership[0].guest_value);
    try std.testing.expectEqual(transferred_value, mapping.ownership[0].transferred_value);
    try std.testing.expectEqual(released_value, mapping.ownership[0].released_value);
}

fn record_layout(contract: producer_contract.ProducerContract) p3_async_manifest.RecordLayout {
    return switch (contract.payload) {
        .record => |layout| layout,
        else => unreachable,
    };
}

fn expect_record(contract: producer_contract.ProducerContract, name: []const u8, byte_size: u32, fields: []const ExpectedField) !void {
    const layout = record_layout(contract);
    try std.testing.expectEqualStrings(name, layout.name);
    try std.testing.expectEqual(byte_size, layout.byte_size);
    try std.testing.expectEqual(fields.len, layout.fields.len);
    for (fields, 0..) |field, index| {
        try std.testing.expectEqualStrings(field.name, layout.fields[index].name);
        try std.testing.expectEqual(field.offset, layout.fields[index].offset);
    }
}

fn expect_owned_paths(contract: producer_contract.ProducerContract, leaves: []const []const []const u8, parents: []const []const []const u8) !void {
    try std.testing.expectEqual(leaves.len, contract.ownership.leaves.len);
    try std.testing.expectEqual(parents.len, contract.ownership.parents.len);
    for (leaves, 0..) |path, index| try expect_path(contract.ownership.leaves[index].path, path);
    for (parents, 0..) |path, index| try expect_path(contract.ownership.parents[index].path, path);
}

fn expect_path(actual: []const []const u8, expected: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, 0..) |segment, index| try std.testing.expectEqualStrings(segment, actual[index]);
}

fn expect_list_allocations(contract: producer_contract.ProducerContract, expected: []const ExpectedAllocation) !void {
    try std.testing.expectEqual(expected.len, contract.list_allocations.len);
    for (expected, 0..) |allocation, index| {
        const actual = contract.list_allocations[index];
        try expect_path(actual.path, allocation.path);
        try std.testing.expectEqual(allocation.pointer_offset, actual.pointer_offset);
        try std.testing.expectEqual(allocation.length_offset, actual.length_offset);
        try std.testing.expectEqual(allocation.element_stride, actual.element_stride);
        try std.testing.expectEqual(allocation.max_items, actual.max_items);
    }
}

fn expect_list_payload(contract: producer_contract.ProducerContract, pointer_offset: u32, length_offset: u32, stride: u32, max_items: u32) !void {
    const layout = switch (contract.payload) {
        .list => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(pointer_offset, layout.pointer_offset);
    try std.testing.expectEqual(length_offset, layout.length_offset);
    try std.testing.expectEqual(stride, layout.element_stride);
    try std.testing.expectEqual(max_items, layout.max_items);
}

fn assert_batched_mixed(
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
) !void {
    var events: [256]probe.LifecycleEvent = undefined;
    var prefix_length: usize = 0;
    for (0..@as(usize, @intCast(report.assets_per_group))) |asset_index| {
        try append_event(&events, &prefix_length, .{ .acquire = .{ .group_index = 0, .asset_index = @intCast(asset_index) } });
    }
    try append_event(&events, &prefix_length, .{ .write_complete = 0 });
    try append_event(&events, &prefix_length, .{ .transfer_commit = 0 });
    try append_cleanup_and_terminal(&events, &prefix_length, contract);
    try std.testing.expectError(
        error.CleanupBeforeAssets,
        probe.run(lifecycle_program(report.route_id, contract, mapping, events[0..prefix_length])),
    );

    const trace = try batched_mixed_trace(&events, report, contract);
    const observation = try probe.run(lifecycle_program(report.route_id, contract, mapping, trace));
    const model = try probe.derive_model_for_test(lifecycle_program(report.route_id, contract, mapping, &.{}));
    const per_group = disposition_counts(.{
        .assets = model.assets,
        .asset_count = model.assets_per_group,
        .group_count = 1,
        .assets_per_group = model.assets_per_group,
    });
    try std.testing.expectEqual(@as(u32, 2), report.group_count);
    try std.testing.expectEqual(per_group.resources, observation.transferred_count);
    try std.testing.expectEqual(per_group.list_backing + model.assets_per_group, observation.released_count);
    try std.testing.expectEqual(report.asset_count, observation.acquired_count);
    try std.testing.expectEqual(probe.TerminalState.completed, observation.terminal_state);
}

fn assert_repeat(
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
) !void {
    var first_events: [256]probe.LifecycleEvent = undefined;
    var second_events: [256]probe.LifecycleEvent = undefined;
    const first = try probe.run(lifecycle_program(report.route_id, contract, mapping, try success_trace(&first_events, report, contract)));
    const second = try probe.run(lifecycle_program(report.route_id, contract, mapping, try success_trace(&second_events, report, contract)));
    try std.testing.expectEqual(first, second);
}

fn assert_incomplete_group(
    report: probe.ProgramReport,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
) !void {
    if (report.group_count != 1 or report.assets_per_group < 2) return error.TestUnexpectedResult;
    var events: [256]probe.LifecycleEvent = undefined;
    var length: usize = 0;
    try append_event(&events, &length, .{ .acquire = .{ .group_index = 0, .asset_index = 0 } });
    try append_event(&events, &length, .{ .write_complete = 0 });
    try std.testing.expectError(
        error.WriteIncomplete,
        probe.run(lifecycle_program(report.route_id, contract, mapping, events[0..length])),
    );
}
