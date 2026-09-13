const std = @import("std");
const producer_contract = @import("codegen_component_producer_contract.zig");
const mapping_probe = @import("codegen_component_producer_mapping_probe.zig");
const probe = @import("codegen_component_producer_lifecycle_state_probe.zig");

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
