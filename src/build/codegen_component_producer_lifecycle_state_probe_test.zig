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
        .ownership = .{ .leaves = &.{}, .parents = &.{} },
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
