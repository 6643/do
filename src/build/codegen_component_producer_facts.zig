const std = @import("std");

/// Immutable producer layout facts shared by production consumers and probes.
pub const FactError = error{
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
};

pub const FrameRole = enum { result_tag, result_payload, waitable, readable, writable, ownership_state, subtask, pending_write, mode, payload, resource_handle, list_pointer, list_length, list_element_area };
pub const FrameFact = struct { name: []const u8, offset: u32, width: u32, alignment: u32, role: FrameRole };
pub const OwnershipEncoding = enum { scalar, mask, batched_scalar };
pub const OwnershipFact = struct { name: []const u8, encoding: OwnershipEncoding, state_offset: u32, guest_value: u32, transferred_value: u32, released_value: u32 };
pub const CanonicalBinding = struct { name: []const u8, canonical_offset: u32, payload_size: u32, frame_offset: u32, width: u32 };
pub const LifecycleAnchor = struct { name: []const u8, required_text: []const []const u8, ordered_anchors: []const []const u8 };
pub const MarkerBinding = struct { name: []const u8, expected_value: ?[]const u8 = null };

pub const RouteFrameFacts = struct {
    route_id: []const u8,
    descriptor_id: []const u8 = "",
    template_name: []const u8 = "",
    frame_size: u32,
    frames: []const FrameFact,
    ownership: []const OwnershipFact,
    bindings: []const CanonicalBinding,
    lifecycle: []const LifecycleAnchor,
    markers: []const MarkerBinding = &.{},
};

pub const FactReport = struct {
    route_id: []const u8,
    frame_count: usize,
    ownership_count: usize,
    binding_count: usize,
    lifecycle_count: usize,
};

pub const direct_route_id = "owned-record-direct";
pub const direct_descriptor_id = "do:g6-2-owned-record-producer@0.1.0";
pub const direct_descriptor_hash = "6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace";

const direct_frames = [_]FrameFact{
    .{ .name = "result-tag", .offset = 0, .width = 4, .alignment = 4, .role = .result_tag },
    .{ .name = "result-payload", .offset = 4, .width = 4, .alignment = 4, .role = .result_payload },
    .{ .name = "waitable-set", .offset = 8, .width = 4, .alignment = 4, .role = .waitable },
    .{ .name = "readable", .offset = 12, .width = 4, .alignment = 4, .role = .readable },
    .{ .name = "writable", .offset = 16, .width = 4, .alignment = 4, .role = .writable },
    .{ .name = "ownership-state", .offset = 20, .width = 4, .alignment = 4, .role = .ownership_state },
    .{ .name = "sink-subtask", .offset = 32, .width = 4, .alignment = 4, .role = .subtask },
    .{ .name = "pending-write", .offset = 36, .width = 4, .alignment = 4, .role = .pending_write },
    .{ .name = "mode", .offset = 40, .width = 4, .alignment = 4, .role = .mode },
    .{ .name = "record-slot", .offset = 64, .width = 4, .alignment = 4, .role = .resource_handle },
};

const direct_ownership = [_]OwnershipFact{
    .{ .name = "resource-or-list", .encoding = .scalar, .state_offset = 20, .guest_value = 1, .transferred_value = 2, .released_value = 3 },
};

const direct_bindings = [_]CanonicalBinding{
    .{ .name = "ticket", .canonical_offset = 0, .payload_size = 4, .frame_offset = 64, .width = 4 },
};

const direct_lifecycle = [_]LifecycleAnchor{
    .{
        .name = "record-lifecycle",
        .required_text = &.{ "(func $release-guest-record", "(func $transfer-record", "(func $post-transfer-cancel", "(func $cleanup" },
        .ordered_anchors = &.{ "(func $release-guest-record", "(func $transfer-record", "(func $post-transfer-cancel", "(func $cleanup" },
    },
};

const direct_markers = [_]MarkerBinding{
    .{ .name = "producer-record-byte-size", .expected_value = "4" },
    .{ .name = "producer-record-ticket-offset", .expected_value = "0" },
    .{ .name = "producer-stream-capacity", .expected_value = "1" },
    .{ .name = "producer-ticket-seed", .expected_value = "111" },
    .{ .name = "producer-record-transfer" },
    .{ .name = "producer-resource-drop-exactly-once" },
    .{ .name = "producer-child-before-parent-cleanup" },
};

pub fn direct_route_facts() RouteFrameFacts {
    return .{
        .route_id = direct_route_id,
        .descriptor_id = direct_descriptor_id,
        .template_name = "owned_record_stream_producer_template.wat",
        .frame_size = 128,
        .frames = &direct_frames,
        .ownership = &direct_ownership,
        .bindings = &direct_bindings,
        .lifecycle = &direct_lifecycle,
        .markers = &direct_markers,
    };
}

pub fn route_facts_equal(left: RouteFrameFacts, right: RouteFrameFacts) bool {
    if (!std.mem.eql(u8, left.route_id, right.route_id) or
        !std.mem.eql(u8, left.descriptor_id, right.descriptor_id) or
        !std.mem.eql(u8, left.template_name, right.template_name) or
        left.frame_size != right.frame_size or left.frames.len != right.frames.len or
        left.ownership.len != right.ownership.len or left.bindings.len != right.bindings.len or
        left.lifecycle.len != right.lifecycle.len or left.markers.len != right.markers.len)
    {
        return false;
    }

    for (left.frames, right.frames) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or a.offset != b.offset or a.width != b.width or
            a.alignment != b.alignment or a.role != b.role) return false;
    }
    for (left.ownership, right.ownership) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or a.encoding != b.encoding or a.state_offset != b.state_offset or
            a.guest_value != b.guest_value or a.transferred_value != b.transferred_value or
            a.released_value != b.released_value) return false;
    }
    for (left.bindings, right.bindings) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or a.canonical_offset != b.canonical_offset or
            a.payload_size != b.payload_size or a.frame_offset != b.frame_offset or a.width != b.width) return false;
    }
    for (left.lifecycle, right.lifecycle) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or !string_lists_equal(a.required_text, b.required_text) or
            !string_lists_equal(a.ordered_anchors, b.ordered_anchors)) return false;
    }
    for (left.markers, right.markers) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or !optional_string_equal(a.expected_value, b.expected_value)) return false;
    }
    return true;
}

fn string_lists_equal(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.mem.eql(u8, a, b)) return false;
    return true;
}

fn optional_string_equal(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

pub fn validate_route_facts(facts: RouteFrameFacts) FactError!void {
    _ = try validate(facts);
}

pub fn validate(facts: RouteFrameFacts) FactError!FactReport {
    if (facts.route_id.len == 0 or facts.descriptor_id.len == 0) return error.InvalidIdentity;
    if (facts.frame_size == 0 or facts.frames.len == 0 or facts.ownership.len == 0 or facts.bindings.len == 0 or facts.lifecycle.len == 0) return error.InvalidFrameSize;
    for (facts.frames, 0..) |field, index| {
        if (field.name.len == 0 or field.width == 0 or field.alignment == 0) return error.InvalidFrame;
        if (field.offset % field.alignment != 0) return error.FrameMisaligned;
        try range(facts.frame_size, field.offset, field.width, error.FrameOutside);
        for (facts.frames[0..index]) |prior| if (overlap(prior.offset, prior.width, field.offset, field.width)) return error.FrameOverlap;
    }
    for (facts.ownership) |ownership| {
        if (ownership.name.len == 0 or ownership.guest_value == ownership.transferred_value) return error.InvalidOwnership;
        if (ownership.encoding != .mask and (ownership.guest_value == ownership.released_value or ownership.transferred_value == ownership.released_value)) return error.InvalidOwnership;
        try range(facts.frame_size, ownership.state_offset, 4, error.OwnershipStateOutsideFrame);
    }
    for (facts.bindings, 0..) |binding, index| {
        if (binding.name.len == 0 or binding.width == 0 or binding.payload_size == 0) return error.InvalidBinding;
        try range(binding.payload_size, binding.canonical_offset, binding.width, error.BindingOutsidePayload);
        try range(facts.frame_size, binding.frame_offset, binding.width, error.BindingOutsideFrame);
        for (facts.bindings[0..index]) |prior| {
            if (overlap(prior.canonical_offset, prior.width, binding.canonical_offset, binding.width) or
                overlap(prior.frame_offset, prior.width, binding.frame_offset, binding.width)) return error.BindingOverlap;
        }
    }
    for (facts.lifecycle) |lifecycle| {
        if (lifecycle.name.len == 0 or lifecycle.required_text.len == 0 or lifecycle.ordered_anchors.len == 0) return error.MissingLifecycle;
        for (lifecycle.required_text) |required| if (required.len == 0) return error.MissingLifecycle;
        for (lifecycle.ordered_anchors) |anchor| if (anchor.len == 0) return error.MissingLifecycle;
    }
    return .{ .route_id = facts.route_id, .frame_count = facts.frames.len, .ownership_count = facts.ownership.len, .binding_count = facts.bindings.len, .lifecycle_count = facts.lifecycle.len };
}

fn range(limit: u32, offset: u32, width: u32, comptime failure: FactError) FactError!void {
    if (width == 0 or offset > limit or width > limit - offset) return failure;
}

fn overlap(left_offset: u32, left_width: u32, right_offset: u32, right_width: u32) bool {
    return left_offset < right_offset +% right_width and right_offset < left_offset +% left_width;
}
