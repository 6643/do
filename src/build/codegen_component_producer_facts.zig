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
