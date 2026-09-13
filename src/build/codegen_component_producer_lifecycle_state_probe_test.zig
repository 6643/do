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
