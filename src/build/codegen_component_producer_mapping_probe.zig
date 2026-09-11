const std = @import("std");

/// Probe errors are deliberately separate from producer/runtime errors. The
/// probe is a read-only audit boundary and must never select a route or emit
/// WAT when a fact is inconsistent.
pub const ProbeError = error{
    InvalidIdentity,
    InvalidFrameSize,
    InvalidFrame,
    FrameOutside,
    FrameMisaligned,
    FrameOverlap,
    InvalidOwnership,
    OwnershipStateOutsideFrame,
    InvalidBinding,
    BindingOutsidePayload,
    BindingOutsideFrame,
    BindingOverlap,
    MissingLifecycle,
    LifecycleOrder,
    MissingMarker,
    MarkerValueMismatch,
    TemplateFragmentOrder,
    CanonicalParity,
    DuplicateCanonicalSegment,
};

pub const FrameRole = enum {
    result_tag,
    result_payload,
    waitable,
    readable,
    writable,
    ownership_state,
    subtask,
    pending_write,
    mode,
    payload,
    resource_handle,
    list_pointer,
    list_length,
    list_element_area,
};

pub const FrameFact = struct {
    name: []const u8,
    offset: u32,
    width: u32,
    alignment: u32,
    role: FrameRole,
};

pub const OwnershipEncoding = enum {
    scalar,
    mask,
    batched_scalar,
};

pub const OwnershipFact = struct {
    name: []const u8,
    encoding: OwnershipEncoding,
    state_offset: u32,
    guest_value: u32,
    transferred_value: u32,
    released_value: u32,
};

pub const BindingFact = struct {
    name: []const u8,
    canonical_offset: u32,
    payload_size: u32,
    frame_offset: u32,
    width: u32,
};

pub const LifecycleFact = struct {
    name: []const u8,
    required_text: []const []const u8,
    ordered_anchors: []const []const u8,
};

pub const MarkerFact = struct {
    name: []const u8,
    expected_value: ?[]const u8 = null,
};

pub const TemplateFact = struct {
    route_id: []const u8,
    template_name: []const u8,
    frame_size: u32,
    frames: []const FrameFact,
    ownership: []const OwnershipFact,
    bindings: []const BindingFact,
    lifecycle: []const LifecycleFact,
    markers: []const MarkerFact = &.{},
};

pub const FactReport = struct {
    route_id: []const u8,
    frame_count: usize,
    ownership_count: usize,
    binding_count: usize,
    lifecycle_count: usize,
};

pub const TemplateObservation = struct {
    route_id: []const u8,
    marker_count: usize,
    lifecycle_count: usize,
    first_anchor_offset: usize,
    last_anchor_offset: usize,
};

pub const ParityObservation = struct {
    canonical_prefix_len: usize,
    canonical_suffix_len: usize,
    insertion_len: usize,
};

/// Validate facts without allocating, parsing WAT, or mutating the caller's
/// slices. Zero remains a valid offset; only an empty fact is considered
/// missing.
pub fn validate_facts(fact: TemplateFact) ProbeError!FactReport {
    if (fact.route_id.len == 0 or fact.template_name.len == 0) {
        return error.InvalidIdentity;
    }
    if (fact.frame_size == 0 or fact.frames.len == 0 or fact.ownership.len == 0 or
        fact.bindings.len == 0 or fact.lifecycle.len == 0)
    {
        return error.InvalidFrameSize;
    }

    for (fact.frames, 0..) |field, index| {
        if (field.name.len == 0 or field.width == 0 or field.alignment == 0) {
            return error.InvalidFrame;
        }
        if (field.offset % field.alignment != 0) return error.FrameMisaligned;
        try validate_range(fact.frame_size, field.offset, field.width, error.FrameOutside);
        for (fact.frames[0..index]) |prior| {
            if (ranges_overlap(prior.offset, prior.width, field.offset, field.width)) {
                return error.FrameOverlap;
            }
        }
    }

    for (fact.ownership) |ownership| {
        if (ownership.name.len == 0 or ownership.guest_value == ownership.transferred_value) {
            return error.InvalidOwnership;
        }
        if (ownership.encoding != .mask and
            (ownership.guest_value == ownership.released_value or
                ownership.transferred_value == ownership.released_value))
        {
            return error.InvalidOwnership;
        }
        try validate_range(fact.frame_size, ownership.state_offset, 4, error.OwnershipStateOutsideFrame);
    }

    for (fact.bindings, 0..) |binding, index| {
        if (binding.name.len == 0 or binding.width == 0 or binding.payload_size == 0) {
            return error.InvalidBinding;
        }
        try validate_range(binding.payload_size, binding.canonical_offset, binding.width, error.BindingOutsidePayload);
        try validate_range(fact.frame_size, binding.frame_offset, binding.width, error.BindingOutsideFrame);
        for (fact.bindings[0..index]) |prior| {
            if (ranges_overlap(prior.frame_offset, prior.width, binding.frame_offset, binding.width)) {
                return error.BindingOverlap;
            }
        }
    }

    for (fact.lifecycle) |lifecycle| {
        if (lifecycle.name.len == 0 or lifecycle.required_text.len == 0 or lifecycle.ordered_anchors.len == 0) {
            return error.MissingLifecycle;
        }
        for (lifecycle.required_text) |required| {
            if (required.len == 0) return error.MissingLifecycle;
        }
        for (lifecycle.ordered_anchors) |anchor| {
            if (anchor.len == 0) return error.MissingLifecycle;
        }
    }

    return .{
        .route_id = fact.route_id,
        .frame_count = fact.frames.len,
        .ownership_count = fact.ownership.len,
        .binding_count = fact.bindings.len,
        .lifecycle_count = fact.lifecycle.len,
    };
}

const record_frames = [_]FrameFact{
    .{ .name = "result-tag", .offset = 0, .width = 4, .alignment = 4, .role = .result_tag },
    .{ .name = "result-payload", .offset = 4, .width = 4, .alignment = 4, .role = .result_payload },
    .{ .name = "waitable-set", .offset = 8, .width = 4, .alignment = 4, .role = .waitable },
    .{ .name = "readable", .offset = 12, .width = 4, .alignment = 4, .role = .readable },
    .{ .name = "writable", .offset = 16, .width = 4, .alignment = 4, .role = .writable },
    .{ .name = "ownership-state", .offset = 20, .width = 4, .alignment = 4, .role = .ownership_state },
    .{ .name = "sink-subtask", .offset = 32, .width = 4, .alignment = 4, .role = .subtask },
    .{ .name = "pending-write", .offset = 36, .width = 4, .alignment = 4, .role = .pending_write },
    .{ .name = "mode", .offset = 40, .width = 4, .alignment = 4, .role = .mode },
};

const record_direct_frames = [_]FrameFact{
    record_frames[0], record_frames[1], record_frames[2], record_frames[3], record_frames[4],
    record_frames[5], record_frames[6], record_frames[7], record_frames[8], .{ .name = "record-slot", .offset = 64, .width = 4, .alignment = 4, .role = .resource_handle },
};

const record_pair_frames = [_]FrameFact{
    record_frames[0],                                                                              record_frames[1], record_frames[2], record_frames[3], record_frames[4],
    record_frames[5],                                                                              record_frames[6], record_frames[7], record_frames[8], .{ .name = "left-slot", .offset = 64, .width = 4, .alignment = 4, .role = .resource_handle },
    .{ .name = "right-slot", .offset = 68, .width = 4, .alignment = 4, .role = .resource_handle },
};

const record_triple_frames = [_]FrameFact{
    record_frames[0],                                                                               record_frames[1],                                                                              record_frames[2], record_frames[3], record_frames[4],
    record_frames[5],                                                                               record_frames[6],                                                                              record_frames[7], record_frames[8], .{ .name = "left-slot", .offset = 64, .width = 4, .alignment = 4, .role = .resource_handle },
    .{ .name = "middle-slot", .offset = 68, .width = 4, .alignment = 4, .role = .resource_handle }, .{ .name = "right-slot", .offset = 72, .width = 4, .alignment = 4, .role = .resource_handle },
};

const record_list_frames = [_]FrameFact{
    record_frames[0],                                                                           record_frames[1],                                                                                      record_frames[2], record_frames[3], record_frames[4],
    record_frames[5],                                                                           record_frames[6],                                                                                      record_frames[7], record_frames[8], .{ .name = "list-pointer", .offset = 24, .width = 4, .alignment = 4, .role = .list_pointer },
    .{ .name = "list-length", .offset = 28, .width = 4, .alignment = 4, .role = .list_length }, .{ .name = "list-entry-slot", .offset = 64, .width = 12, .alignment = 4, .role = .list_element_area },
};

const record_two_list_frames = [_]FrameFact{
    record_frames[0],                                                                                 record_frames[1],                                                                                    record_frames[2],                                                                                  record_frames[3],                                                                                          record_frames[4],
    record_frames[5],                                                                                 record_frames[6],                                                                                    record_frames[7],                                                                                  record_frames[8],                                                                                          .{ .name = "first-list-pointer", .offset = 24, .width = 4, .alignment = 4, .role = .list_pointer },
    .{ .name = "first-list-length", .offset = 28, .width = 4, .alignment = 4, .role = .list_length }, .{ .name = "second-list-pointer", .offset = 48, .width = 4, .alignment = 4, .role = .list_pointer }, .{ .name = "second-list-length", .offset = 52, .width = 4, .alignment = 4, .role = .list_length }, .{ .name = "two-list-entry-slot", .offset = 64, .width = 20, .alignment = 4, .role = .list_element_area },
};

const list_frames = [_]FrameFact{
    record_frames[0],                                                                           record_frames[1],                                                                                       record_frames[2], record_frames[3], record_frames[4],
    record_frames[5],                                                                           record_frames[6],                                                                                       record_frames[7], record_frames[8], .{ .name = "list-pointer", .offset = 24, .width = 4, .alignment = 4, .role = .list_pointer },
    .{ .name = "list-length", .offset = 28, .width = 4, .alignment = 4, .role = .list_length }, .{ .name = "list-element-area", .offset = 44, .width = 4, .alignment = 4, .role = .list_element_area },
};

const batch_frames = [_]FrameFact{
    record_frames[0],                                                                                     record_frames[1],                                                                                     record_frames[2],                                                                                     record_frames[3],                                                                                   record_frames[4],
    record_frames[5],                                                                                     record_frames[6],                                                                                     record_frames[7],                                                                                     record_frames[8],                                                                                   .{ .name = "batch-1-ownership-state", .offset = 44, .width = 4, .alignment = 4, .role = .ownership_state },
    .{ .name = "batch-0-list-pointer", .offset = 24, .width = 4, .alignment = 4, .role = .list_pointer }, .{ .name = "batch-0-list-length", .offset = 28, .width = 4, .alignment = 4, .role = .list_length },   .{ .name = "batch-1-list-pointer", .offset = 48, .width = 4, .alignment = 4, .role = .list_pointer }, .{ .name = "batch-1-list-length", .offset = 52, .width = 4, .alignment = 4, .role = .list_length }, .{ .name = "batch-0-pointer", .offset = 64, .width = 4, .alignment = 4, .role = .list_element_area },
    .{ .name = "batch-0-length", .offset = 68, .width = 4, .alignment = 4, .role = .list_element_area },  .{ .name = "batch-1-pointer", .offset = 72, .width = 4, .alignment = 4, .role = .list_element_area }, .{ .name = "batch-1-length", .offset = 76, .width = 4, .alignment = 4, .role = .list_element_area },
};

const scalar_ownership = [_]OwnershipFact{
    .{ .name = "resource-or-list", .encoding = .scalar, .state_offset = 20, .guest_value = 1, .transferred_value = 2, .released_value = 3 },
};

const nested_ownership = [_]OwnershipFact{
    .{ .name = "nested-inner-ticket", .encoding = .mask, .state_offset = 20, .guest_value = 1, .transferred_value = 2, .released_value = 0 },
};

const pair_ownership = [_]OwnershipFact{
    .{ .name = "resource-pair", .encoding = .mask, .state_offset = 20, .guest_value = 3, .transferred_value = 4, .released_value = 0 },
};

const triple_ownership = [_]OwnershipFact{
    .{ .name = "resource-triple", .encoding = .mask, .state_offset = 20, .guest_value = 7, .transferred_value = 8, .released_value = 0 },
};

const batched_ownership = [_]OwnershipFact{
    .{ .name = "batch-0", .encoding = .batched_scalar, .state_offset = 20, .guest_value = 1, .transferred_value = 2, .released_value = 3 },
    .{ .name = "batch-1", .encoding = .batched_scalar, .state_offset = 44, .guest_value = 1, .transferred_value = 2, .released_value = 3 },
};

const direct_bindings = [_]BindingFact{
    .{ .name = "ticket", .canonical_offset = 0, .payload_size = 4, .frame_offset = 64, .width = 4 },
};

const pair_bindings = [_]BindingFact{
    .{ .name = "left", .canonical_offset = 0, .payload_size = 8, .frame_offset = 64, .width = 4 },
    .{ .name = "right", .canonical_offset = 4, .payload_size = 8, .frame_offset = 68, .width = 4 },
};

const triple_bindings = [_]BindingFact{
    .{ .name = "left", .canonical_offset = 0, .payload_size = 12, .frame_offset = 64, .width = 4 },
    .{ .name = "middle", .canonical_offset = 4, .payload_size = 12, .frame_offset = 68, .width = 4 },
    .{ .name = "right", .canonical_offset = 8, .payload_size = 12, .frame_offset = 72, .width = 4 },
};

const record_list_bindings = [_]BindingFact{
    .{ .name = "record-entry", .canonical_offset = 0, .payload_size = 12, .frame_offset = 64, .width = 12 },
};

const two_list_bindings = [_]BindingFact{
    .{ .name = "two-list-entry", .canonical_offset = 0, .payload_size = 20, .frame_offset = 64, .width = 20 },
};

const list_bindings = [_]BindingFact{
    .{ .name = "list-pointer", .canonical_offset = 0, .payload_size = 8, .frame_offset = 24, .width = 4 },
    .{ .name = "list-length", .canonical_offset = 4, .payload_size = 8, .frame_offset = 28, .width = 4 },
};

const batch_bindings = [_]BindingFact{
    .{ .name = "batch-0-pointer", .canonical_offset = 0, .payload_size = 16, .frame_offset = 24, .width = 4 },
    .{ .name = "batch-0-length", .canonical_offset = 4, .payload_size = 16, .frame_offset = 28, .width = 4 },
    .{ .name = "batch-1-pointer", .canonical_offset = 8, .payload_size = 16, .frame_offset = 48, .width = 4 },
    .{ .name = "batch-1-length", .canonical_offset = 12, .payload_size = 16, .frame_offset = 52, .width = 4 },
};

const record_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "4" },
    .{ .name = "producer-record-ticket-offset", .expected_value = "0" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-ticket-seed", .expected_value = "111" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const list_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "12" },
    .{ .name = "producer-record-alignment", .expected_value = "4" },
    .{ .name = "producer-record-values-pointer-offset", .expected_value = "0" },
    .{ .name = "producer-record-values-length-offset", .expected_value = "4" },
    .{ .name = "producer-record-ticket-offset", .expected_value = "8" },
    .{ .name = "producer-list-stride", .expected_value = "4" },
    .{ .name = "producer-list-capacity", .expected_value = "3" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-ticket-seed", .expected_value = "111" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-list-release-exactly-once" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const two_list_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "20" },
    .{ .name = "producer-record-alignment", .expected_value = "4" },
    .{ .name = "producer-first-pointer-offset", .expected_value = "0" },
    .{ .name = "producer-first-length-offset", .expected_value = "4" },
    .{ .name = "producer-second-pointer-offset", .expected_value = "8" },
    .{ .name = "producer-second-length-offset", .expected_value = "12" },
    .{ .name = "producer-ticket-offset", .expected_value = "16" },
    .{ .name = "producer-list-stride", .expected_value = "4" },
    .{ .name = "producer-list-capacity", .expected_value = "3" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-ticket-seed", .expected_value = "111" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-list-release-exactly-once" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const pair_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "8" },
    .{ .name = "producer-record-left-offset", .expected_value = "0" },
    .{ .name = "producer-record-right-offset", .expected_value = "4" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-left-ticket-seed", .expected_value = "111" },
    .{ .name = "producer-right-ticket-seed", .expected_value = "222" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const triple_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "12" },
    .{ .name = "producer-record-left-offset", .expected_value = "0" },
    .{ .name = "producer-record-middle-offset", .expected_value = "4" },
    .{ .name = "producer-record-right-offset", .expected_value = "8" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-input-mode" },
    .{ .name = "producer-left-ticket-seed-param" },
    .{ .name = "producer-middle-ticket-seed-param" },
    .{ .name = "producer-right-ticket-seed-param" },
    .{ .name = "producer-seed-order", .expected_value = "left then middle then right" },
    .{ .name = "producer-input-word-count", .expected_value = "4" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const nested_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "4" },
    .{ .name = "producer-record-alignment", .expected_value = "4" },
    .{ .name = "producer-nested-ticket-offset", .expected_value = "0" },
    .{ .name = "producer-nested-path", .expected_value = "inner.ticket" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-source-signature", .expected_value = "(i32) -> (i32)" },
    .{ .name = "producer-ticket-seed", .expected_value = "111" },
    .{ .name = "producer-input-mode" },
    .{ .name = "producer-ownership-mask", .expected_value = "guest=1 transferred=2" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const mixed_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "8" },
    .{ .name = "producer-record-alignment", .expected_value = "4" },
    .{ .name = "producer-record-code-offset", .expected_value = "0" },
    .{ .name = "producer-record-ticket-offset", .expected_value = "4" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-ticket-seed", .expected_value = "111" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const parameterized_pair_markers = [_]MarkerFact{
    .{ .name = "producer-record-byte-size", .expected_value = "8" },
    .{ .name = "producer-record-left-offset", .expected_value = "0" },
    .{ .name = "producer-record-right-offset", .expected_value = "4" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-input-mode" },
    .{ .name = "producer-left-ticket-seed-param" },
    .{ .name = "producer-right-ticket-seed-param" },
    .{ .name = "producer-seed-order", .expected_value = "left then right" },
    .{ .name = "producer-input-word-count", .expected_value = "3" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

const cmin_markers = [_]MarkerFact{
    .{ .name = "producer-list-pointer" },
    .{ .name = "producer-list-length" },
    .{ .name = "producer-list-element-stride" },
    .{ .name = "producer-list-ticket-offset" },
    .{ .name = "producer-stream-capacity" },
};

const scalar_list_markers = [_]MarkerFact{
    .{ .name = "producer-list-pointer" },
    .{ .name = "producer-list-length" },
    .{ .name = "producer-list-element-stride" },
    .{ .name = "producer-list-capacity" },
    .{ .name = "producer-stream-item-slot" },
    .{ .name = "producer-list-release-exactly-once" },
    .{ .name = "producer-list-transfer" },
};

const batch_markers = [_]MarkerFact{
    .{ .name = "producer-list-pointer" },
    .{ .name = "producer-list-length" },
    .{ .name = "producer-list-pointer-batch-1" },
    .{ .name = "producer-list-length-batch-1" },
    .{ .name = "producer-list-element-stride" },
    .{ .name = "producer-list-ticket-offset" },
    .{ .name = "producer-stream-capacity" },
    .{ .name = "producer-batch-child-before-parent-cleanup" },
    .{ .name = "producer-batch-list-release" },
};

const record_lifecycle = [_]LifecycleFact{
    .{
        .name = "record-lifecycle",
        .required_text = &.{ "(func $release-guest-record", "(func $transfer-record", "(func $post-transfer-cancel", "(func $cleanup" },
        .ordered_anchors = &.{ "(func $release-guest-record", "(func $transfer-record", "(func $post-transfer-cancel", "(func $cleanup" },
    },
};

const list_lifecycle = [_]LifecycleFact{
    .{
        .name = "list-record-lifecycle",
        .required_text = &.{ "(func $release-guest-record", "(func $transfer-record", "(func $post-transfer-cancel", "(func $cleanup" },
        .ordered_anchors = &.{ "(func $release-guest-record", "(func $transfer-record", "(func $post-transfer-cancel", "(func $cleanup" },
    },
};

const cmin_lifecycle = [_]LifecycleFact{
    .{
        .name = "list-lifecycle",
        .required_text = &.{ "(func $release-guest-list", "(func $transfer-list", "(func $cleanup" },
        .ordered_anchors = &.{ "(func $release-guest-list", "(func $transfer-list", "(func $cleanup" },
    },
};

const scalar_list_lifecycle = [_]LifecycleFact{
    .{
        .name = "scalar-list-lifecycle",
        .required_text = &.{ "[producer-list-release-exactly-once]", "[producer-list-transfer]", "(func $release-guest-list", "(func $transfer-list", "(func $cleanup" },
        .ordered_anchors = &.{ "(func $release-guest-list", "(func $transfer-list", "(func $cleanup" },
    },
};

const batch_lifecycle = [_]LifecycleFact{
    .{
        .name = "batch-lifecycle",
        .required_text = &.{ "[producer-batch-child-before-parent-cleanup]", "[producer-batch-list-release]", "(func $batch-release", "(func $batch-transfer", "(func $cleanup-batched" },
        .ordered_anchors = &.{ "(func $batch-release", "(func $batch-transfer", "(func $cleanup-batched" },
    },
};

pub const checked_in_template_facts: []const TemplateFact = &[_]TemplateFact{
    .{ .route_id = "owned-record-direct", .template_name = "owned_record_stream_producer_template.wat", .frame_size = 128, .frames = &record_direct_frames, .ownership = &scalar_ownership, .bindings = &direct_bindings, .lifecycle = &record_lifecycle, .markers = &record_markers },
    .{ .route_id = "owned-record-list", .template_name = "list_owned_record_stream_producer_template.wat", .frame_size = 128, .frames = &record_list_frames, .ownership = &scalar_ownership, .bindings = &record_list_bindings, .lifecycle = &list_lifecycle, .markers = &list_markers },
    .{ .route_id = "owned-record-two-list", .template_name = "two_list_owned_record_stream_producer_template.wat", .frame_size = 128, .frames = &record_two_list_frames, .ownership = &scalar_ownership, .bindings = &two_list_bindings, .lifecycle = &list_lifecycle, .markers = &two_list_markers },
    .{ .route_id = "owned-record-pair", .template_name = "owned_record_pair_stream_producer_template.wat", .frame_size = 128, .frames = &record_pair_frames, .ownership = &pair_ownership, .bindings = &pair_bindings, .lifecycle = &record_lifecycle, .markers = &pair_markers },
    .{ .route_id = "owned-record-triple", .template_name = "owned_record_triple_stream_producer_template.wat", .frame_size = 128, .frames = &record_triple_frames, .ownership = &triple_ownership, .bindings = &triple_bindings, .lifecycle = &record_lifecycle, .markers = &triple_markers },
    .{ .route_id = "owned-record-nested", .template_name = "owned_record_nested_stream_producer_template.wat", .frame_size = 128, .frames = &record_direct_frames, .ownership = &nested_ownership, .bindings = &direct_bindings, .lifecycle = &record_lifecycle, .markers = &nested_markers },
    .{ .route_id = "owned-record-mixed", .template_name = "mixed_owned_record_stream_producer_template.wat", .frame_size = 128, .frames = &record_pair_frames, .ownership = &scalar_ownership, .bindings = &pair_bindings, .lifecycle = &record_lifecycle, .markers = &mixed_markers },
    .{ .route_id = "owned-record-parameterized-pair", .template_name = "parameterized_owned_record_pair_stream_producer_template.wat", .frame_size = 128, .frames = &record_pair_frames, .ownership = &pair_ownership, .bindings = &pair_bindings, .lifecycle = &record_lifecycle, .markers = &parameterized_pair_markers },
    .{ .route_id = "c-min-list", .template_name = "cmin_list_resource_producer_template.wat", .frame_size = 128, .frames = &list_frames, .ownership = &scalar_ownership, .bindings = &list_bindings, .lifecycle = &cmin_lifecycle, .markers = &cmin_markers },
    .{ .route_id = "c-min-dynamic-list", .template_name = "cmin_dynamic_list_resource_producer_template.wat", .frame_size = 128, .frames = &list_frames, .ownership = &scalar_ownership, .bindings = &list_bindings, .lifecycle = &cmin_lifecycle, .markers = &cmin_markers },
    .{ .route_id = "scalar-list", .template_name = "cmin_scalar_list_stream_producer_template.wat", .frame_size = 128, .frames = &list_frames, .ownership = &scalar_ownership, .bindings = &list_bindings, .lifecycle = &scalar_list_lifecycle, .markers = &scalar_list_markers },
    .{ .route_id = "c-min-batched-list", .template_name = "cmin_batched_list_resource_producer_template.wat", .frame_size = 128, .frames = &batch_frames, .ownership = &batched_ownership, .bindings = &batch_bindings, .lifecycle = &batch_lifecycle, .markers = &batch_markers },
};

pub fn fact_for_route(route_id: []const u8) ?*const TemplateFact {
    for (checked_in_template_facts) |*fact| {
        if (std.mem.eql(u8, fact.route_id, route_id)) return fact;
    }
    return null;
}

/// Return the trimmed value following the first `[producer-*]` marker. A
/// marker without a value returns an empty slice; an absent marker returns
/// null. The returned slice borrows `template`.
pub fn marker_value(template: []const u8, marker_name: []const u8) ?[]const u8 {
    if (marker_name.len == 0) return null;
    var needle_buf: [256]u8 = undefined;
    if (marker_name.len + 2 > needle_buf.len) return null;
    needle_buf[0] = '[';
    std.mem.copyForwards(u8, needle_buf[1 .. marker_name.len + 1], marker_name);
    needle_buf[marker_name.len + 1] = ']';
    const needle = needle_buf[0 .. marker_name.len + 2];
    const start = std.mem.indexOf(u8, template, needle) orelse return null;
    const line_start = start + needle.len;
    const line_end = std.mem.indexOfScalarPos(u8, template, line_start, '\n') orelse template.len;
    return std.mem.trim(u8, template[line_start..line_end], " \t\r");
}

/// Scan immutable template text against one fact entry. No WAT is parsed or
/// rewritten; only existing marker/anchor bytes are located and counted.
pub fn decompose_template(template: []const u8, fact: TemplateFact) ProbeError!TemplateObservation {
    _ = try validate_facts(fact);
    if (template.len == 0) return error.MissingMarker;

    var marker_count: usize = 0;
    for (fact.markers) |marker| {
        const value = marker_value(template, marker.name) orelse return error.MissingMarker;
        marker_count += 1;
        if (marker.expected_value) |expected| {
            if (!std.mem.eql(u8, value, expected)) return error.MarkerValueMismatch;
        }
    }

    var first_anchor: ?usize = null;
    var last_anchor: usize = 0;
    var lifecycle_count: usize = 0;
    for (fact.lifecycle) |lifecycle| {
        for (lifecycle.required_text) |required| {
            if (std.mem.indexOf(u8, template, required) == null) return error.MissingLifecycle;
        }
        var cursor: usize = 0;
        for (lifecycle.ordered_anchors) |anchor| {
            const relative = std.mem.indexOfPos(u8, template, cursor, anchor) orelse return error.LifecycleOrder;
            if (first_anchor == null) first_anchor = relative;
            last_anchor = relative + anchor.len;
            cursor = relative + anchor.len;
        }
        lifecycle_count += 1;
    }

    return .{
        .route_id = fact.route_id,
        .marker_count = marker_count,
        .lifecycle_count = lifecycle_count,
        .first_anchor_offset = first_anchor orelse return error.MissingLifecycle,
        .last_anchor_offset = last_anchor,
    };
}

/// Verify that generated WAT preserves the canonical template bytes at the
/// prefix and suffix. Existing emitters may insert route metadata immediately
/// before the final module close; that insertion is reported but never parsed.
pub fn verify_canonical_segments(canonical: []const u8, generated: []const u8) ProbeError!ParityObservation {
    if (canonical.len == 0 or generated.len == 0) return error.CanonicalParity;
    const close = std.mem.lastIndexOf(u8, canonical, "\n)") orelse return error.CanonicalParity;
    const prefix = canonical[0..close];
    const suffix = canonical[close..];
    if (generated.len < prefix.len + suffix.len or
        !std.mem.startsWith(u8, generated, prefix) or
        !std.mem.endsWith(u8, generated, suffix))
    {
        return error.CanonicalParity;
    }

    const insertion = generated[prefix.len .. generated.len - suffix.len];
    var occurrence_count: usize = 0;
    var occurrence_cursor: usize = 0;
    while (std.mem.indexOfPos(u8, generated, occurrence_cursor, canonical)) |occurrence| {
        occurrence_count += 1;
        if (occurrence_count > 1) return error.DuplicateCanonicalSegment;
        occurrence_cursor = occurrence + canonical.len;
    }
    return .{
        .canonical_prefix_len = prefix.len,
        .canonical_suffix_len = suffix.len,
        .insertion_len = insertion.len,
    };
}

fn validate_range(
    limit: u32,
    offset: u32,
    width: u32,
    comptime failure: ProbeError,
) ProbeError!void {
    if (width == 0 or offset > limit or width > limit - offset) return failure;
}

fn ranges_overlap(left_offset: u32, left_width: u32, right_offset: u32, right_width: u32) bool {
    return left_offset < right_offset + right_width and right_offset < left_offset + left_width;
}
