const std = @import("std");
const producer_contract = @import("codegen_component_producer_contract.zig");
const audit = @import("codegen_component_producer_runtime_audit.zig");

const base_fields = [_]audit.RuntimeField{
    .{ .name = "result-tag", .offset = 0, .width = 4, .alignment = 4 },
    .{ .name = "waitable", .offset = 8, .width = 4, .alignment = 4 },
    .{ .name = "stream-readable", .offset = 12, .width = 4, .alignment = 4 },
    .{ .name = "stream-writable", .offset = 16, .width = 4, .alignment = 4 },
    .{ .name = "subtask", .offset = 32, .width = 4, .alignment = 4 },
    .{ .name = "ticket", .offset = 64, .width = 4, .alignment = 4 },
};

const base_states = [_]audit.OwnershipState{
    .{ .name = "guest", .value = 1, .kind = .guest_owned },
    .{ .name = "transferred", .value = 2, .kind = .transferred },
    .{ .name = "released", .value = 3, .kind = .released },
};

const base_control_states = [_]audit.ControlState{
    .{ .name = "ready", .value = 1 },
    .{ .name = "post-transfer-cancel-a", .value = 5 },
    .{ .name = "post-transfer-cancel-b", .value = 7 },
};

const base_cancel_states = [_]u32{ 5, 7 };
const empty_offsets = [_]u32{};
const base_cleanup = [_]audit.CleanupStep{
    .{ .stage = .stream, .symbol = "stream-drop", .offsets = &empty_offsets },
    .{ .stage = .future, .symbol = "future-drop", .offsets = &empty_offsets },
    .{ .stage = .subtask, .symbol = "subtask-drop", .offsets = &.{32} },
    .{ .stage = .waitable, .symbol = "waitable-drop", .offsets = &.{8} },
    .{ .stage = .frame, .symbol = "frame-free", .offsets = &empty_offsets },
};

fn base_runtime() audit.RuntimeAudit {
    return .{
        .route_id = "do:test-producer@0.1.0/consume-via-stream",
        .frame_size = 128,
        .fields = &base_fields,
        .ownership_states = &base_states,
        .control_states = &base_control_states,
        .post_transfer_cancel_states = &base_cancel_states,
        .bindings = &.{
            .{ .name = "ticket", .canonical_offset = 0, .payload_size = 4, .frame_offset = 64, .width = 4 },
        },
        .cleanup_steps = &base_cleanup,
    };
}

fn base_contract() producer_contract.ProducerContract {
    return .{
        .descriptor_id = "do:test-producer@0.1.0/consume-via-stream",
        .source = .{
            .module = "source",
            .import_name = "make-ticket",
            .core_params = &.{},
            .core_results = &.{"i32"},
        },
        .sink = .{
            .module = "sink",
            .member = "consume-via-stream",
            .capacity = 1,
            .read_import = "stream-read",
            .write_import = "stream-write",
            .drop_import = "stream-drop",
        },
        .payload = .{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } },
        .ownership = .{ .leaves = &.{}, .parents = &.{} },
        .terminal = .{
            .close_action = "task-return",
            .abort_action = null,
            .cancel_action = "subtask-cancel",
            .cleanup_order = &.{ .stream, .future, .subtask, .waitable, .frame },
        },
    };
}

fn expect_template_audit(
    route_id: []const u8,
    template: []const u8,
    required: []const []const u8,
    ordered: []const []const u8,
    markers: []const []const u8,
) !void {
    try audit.audit_template(template, .{
        .route_id = route_id,
        .required_fragments = required,
        .ordered_fragments = ordered,
        .required_markers = markers,
        .forbidden_fragments = &.{"__arc_"},
    });
}

test "producer runtime audit accepts zero offset and borrows measured slices" {
    const runtime = base_runtime();
    const report = try audit.validate(runtime);

    try std.testing.expectEqualStrings(runtime.route_id, report.route_id);
    try std.testing.expectEqual(@as(u32, 128), report.frame_size);
    try std.testing.expectEqual(@as(usize, runtime.fields.len), report.field_count);
    try std.testing.expectEqual(@as(usize, runtime.cleanup_steps.len), report.cleanup_count);
    try std.testing.expectEqual(@as(usize, runtime.bindings.len), report.binding_count);
    try std.testing.expectEqual(@as(u32, 0), runtime.fields[0].offset);
}

test "producer runtime audit rejects an offset outside the frame" {
    var fields = base_fields;
    fields[0].offset = 128;
    var runtime = base_runtime();
    runtime.fields = &fields;

    try std.testing.expectError(error.OffsetOutsideFrame, audit.validate(runtime));
}

test "producer runtime audit rejects overlapping frame fields" {
    var fields = base_fields;
    fields[1].offset = 0;
    var runtime = base_runtime();
    runtime.fields = &fields;

    try std.testing.expectError(error.RuntimeOffsetOverlap, audit.validate(runtime));
}

test "producer runtime audit rejects duplicate ownership state values" {
    var states = base_states;
    states[1].value = states[0].value;
    var runtime = base_runtime();
    runtime.ownership_states = &states;

    try std.testing.expectError(error.DuplicateStateValue, audit.validate(runtime));
}

test "producer runtime audit rejects an uncovered post-transfer cancel state" {
    var cancel_states = [_]u32{ 5, 9 };
    var runtime = base_runtime();
    runtime.post_transfer_cancel_states = &cancel_states;

    try std.testing.expectError(error.UncoveredPostTransferCancelState, audit.validate(runtime));
}

test "producer runtime audit rejects a cleanup step without a symbol" {
    var cleanup = base_cleanup;
    cleanup[0].symbol = "";
    var runtime = base_runtime();
    runtime.cleanup_steps = &cleanup;

    try std.testing.expectError(error.MissingCleanupSymbol, audit.validate(runtime));
}

test "producer runtime audit rejects a contract cleanup stage absent from the measured template" {
    var runtime = base_runtime();
    runtime.cleanup_steps = base_cleanup[0..4];

    try std.testing.expectError(error.CleanupStageMismatch, audit.validate_contract(base_contract(), runtime));
}

test "producer runtime audit accepts matching contract cleanup stages" {
    const report = try audit.validate_contract(base_contract(), base_runtime());

    try std.testing.expectEqualStrings(base_contract().descriptor_id, report.route_id);
    try std.testing.expectEqual(@as(usize, base_runtime().cleanup_steps.len), report.cleanup_count);
}

test "producer runtime audit rejects a canonical binding outside its payload" {
    var runtime = base_runtime();
    runtime.bindings = &.{
        .{ .name = "ticket", .canonical_offset = 4, .payload_size = 4, .frame_offset = 64, .width = 4 },
    };

    try std.testing.expectError(error.CanonicalOffsetOutsidePayload, audit.validate(runtime));
}

test "producer runtime audit covers every checked-in producer template" {
    const record_required = &.{ "(func $frame-free", "(func $cleanup", "[producer-child-before-parent-cleanup]" };
    const record_ordered = &.{ "(func $transfer-record", "(func $post-transfer-cancel", "(func $cleanup" };
    const record_markers = &.{ "[producer-record-transfer]", "[producer-resource-drop-exactly-once]" };
    try expect_template_audit("owned-record", @embedFile("owned_record_stream_producer_template.wat"), record_required, record_ordered, record_markers);
    try expect_template_audit("owned-record-list", @embedFile("list_owned_record_stream_producer_template.wat"), record_required, record_ordered, record_markers);
    try expect_template_audit("owned-record-two-list", @embedFile("two_list_owned_record_stream_producer_template.wat"), record_required, record_ordered, record_markers);
    try expect_template_audit("owned-record-pair", @embedFile("owned_record_pair_stream_producer_template.wat"), record_required, record_ordered, record_markers);
    try expect_template_audit("owned-record-triple", @embedFile("owned_record_triple_stream_producer_template.wat"), record_required, record_ordered, record_markers);
    try expect_template_audit("owned-record-nested", @embedFile("owned_record_nested_stream_producer_template.wat"), record_required, record_ordered, record_markers);
    try expect_template_audit("owned-record-mixed", @embedFile("mixed_owned_record_stream_producer_template.wat"), record_required, record_ordered, record_markers);
    try expect_template_audit("owned-record-parameterized-pair", @embedFile("parameterized_owned_record_pair_stream_producer_template.wat"), record_required, record_ordered, record_markers);

    const list_required = &.{ "(func $frame-free", "(func $cleanup" };
    const list_ordered = &.{ "(func $transfer-list", "(func $cleanup" };
    const list_markers = &.{ "[producer-list-element-stride]", "[producer-list-pointer]", "[producer-list-length]" };
    try expect_template_audit("c-min-list", @embedFile("cmin_list_resource_producer_template.wat"), list_required, list_ordered, list_markers);
    try expect_template_audit("c-min-dynamic-list", @embedFile("cmin_dynamic_list_resource_producer_template.wat"), list_required, list_ordered, list_markers);

    const scalar_required = &.{ "(func $frame-free", "(func $cleanup", "[producer-list-release-exactly-once]" };
    const scalar_ordered = &.{ "(func $transfer-list", "(func $cleanup" };
    const scalar_markers = &.{ "[producer-list-element-stride]", "[producer-stream-item-slot]" };
    try expect_template_audit("scalar-list", @embedFile("cmin_scalar_list_stream_producer_template.wat"), scalar_required, scalar_ordered, scalar_markers);

    const batch_required = &.{ "(func $frame-free", "(func $cleanup-batched", "[producer-batch-child-before-parent-cleanup]" };
    const batch_ordered = &.{ "(func $batch-transfer", "(func $cleanup-batched" };
    const batch_markers = &.{ "[producer-batch-transfer-0]", "[producer-batch-transfer-1]", "[producer-batch-list-release]" };
    try expect_template_audit("c-min-batched-list", @embedFile("cmin_batched_list_resource_producer_template.wat"), batch_required, batch_ordered, batch_markers);
}

test "producer runtime audit rejects a missing template fragment" {
    try std.testing.expectError(
        error.MissingTemplateFragment,
        audit.audit_template("(func $cleanup)\n", .{
            .route_id = "missing-fragment",
            .required_fragments = &.{"(func $transfer-record"},
            .ordered_fragments = &.{},
            .required_markers = &.{},
            .forbidden_fragments = &.{},
        }),
    );
}

test "producer runtime audit rejects forbidden template text" {
    try std.testing.expectError(
        error.ForbiddenTemplateFragment,
        audit.audit_template("(func $cleanup)\n;; __arc_release\n", .{
            .route_id = "forbidden-fragment",
            .required_fragments = &.{"(func $cleanup"},
            .ordered_fragments = &.{},
            .required_markers = &.{},
            .forbidden_fragments = &.{"__arc_"},
        }),
    );
}

test "producer runtime audit rejects lifecycle fragment order drift" {
    try std.testing.expectError(
        error.TemplateFragmentOrder,
        audit.audit_template("transfer cleanup\n", .{
            .route_id = "order-drift",
            .required_fragments = &.{},
            .ordered_fragments = &.{ "cleanup", "transfer" },
            .required_markers = &.{},
            .forbidden_fragments = &.{},
        }),
    );
}
