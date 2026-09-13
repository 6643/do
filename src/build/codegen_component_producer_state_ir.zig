const std = @import("std");
const facts = @import("codegen_component_producer_facts.zig");
const producer_contract = @import("codegen_component_producer_contract.zig");

pub const MapError = error{
    InvalidIdentity,
    InvalidContract,
    InvalidFacts,
    InvalidFrame,
    InvalidBinding,
    BindingOverlap,
    OwnershipStateOverlap,
    InvalidMarker,
    InvalidLifecycle,
    BatchAlias,
    UnsupportedBound,
    ZeroSentinel,
};

pub const CanonicalFrameMap = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    frame_size: u32,
    fields: []const facts.FrameFact,
    bindings: []const facts.CanonicalBinding,
    ownership: []const facts.OwnershipFact,
    markers: []const facts.MarkerBinding,
    lifecycle: []const facts.LifecycleAnchor,
};

pub const FrameMapInput = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    contract: producer_contract.ProducerContract,
    frame_facts: facts.RouteFrameFacts,
};

pub fn build_frame_map(input: FrameMapInput) MapError!CanonicalFrameMap {
    if (input.route_id.len == 0 or input.descriptor_id.len == 0 or
        !std.mem.eql(u8, input.route_id, input.frame_facts.route_id) or
        !std.mem.eql(u8, input.descriptor_id, input.frame_facts.descriptor_id) or
        !std.mem.eql(u8, input.descriptor_id, input.contract.descriptor_id))
        return error.InvalidIdentity;

    producer_contract.validate_contract(input.contract) catch |err| switch (err) {
        error.ZeroHandleAbsenceSentinel => return error.ZeroSentinel,
        else => return error.InvalidContract,
    };
    try validate_bounds_and_alias(input.frame_facts, input.contract);
    facts.validate_route_facts(input.frame_facts) catch |err| return map_fact_error(err);

    if (input.frame_facts.frame_size != 128) return error.UnsupportedBound;
    try validate_extra(input.frame_facts, input.contract);

    const map = CanonicalFrameMap{
        .route_id = input.route_id,
        .descriptor_id = input.descriptor_id,
        .frame_size = input.frame_facts.frame_size,
        .fields = input.frame_facts.frames,
        .bindings = input.frame_facts.bindings,
        .ownership = input.frame_facts.ownership,
        .markers = input.frame_facts.markers,
        .lifecycle = input.frame_facts.lifecycle,
    };
    try validate_frame_map(map, input.contract);
    return map;
}

pub fn validate_frame_map(map: CanonicalFrameMap, contract: producer_contract.ProducerContract) MapError!void {
    if (map.route_id.len == 0 or map.descriptor_id.len == 0 or
        !std.mem.eql(u8, map.descriptor_id, contract.descriptor_id))
        return error.InvalidIdentity;
    producer_contract.validate_contract(contract) catch |err| switch (err) {
        error.ZeroHandleAbsenceSentinel => return error.ZeroSentinel,
        else => return error.InvalidContract,
    };
    const route_facts = facts.RouteFrameFacts{
        .route_id = map.route_id,
        .descriptor_id = map.descriptor_id,
        .frame_size = map.frame_size,
        .frames = map.fields,
        .ownership = map.ownership,
        .bindings = map.bindings,
        .lifecycle = map.lifecycle,
        .markers = map.markers,
    };
    try validate_bounds_and_alias(route_facts, contract);
    facts.validate_route_facts(route_facts) catch |err| return map_fact_error(err);
    if (map.frame_size != 128) return error.UnsupportedBound;
    try validate_extra(route_facts, contract);
}

fn validate_bounds_and_alias(route: facts.RouteFrameFacts, contract: producer_contract.ProducerContract) MapError!void {
    if (route.ownership.len + contract.list_allocations.len > 64) return error.UnsupportedBound;
    var pointer_offset: ?u32 = null;
    var length_offset: ?u32 = null;
    for (route.frames) |field| {
        if (field.role == .list_pointer) pointer_offset = field.offset;
        if (field.role == .list_length) length_offset = field.offset;
    }
    if (pointer_offset != null and length_offset != null and pointer_offset.? == length_offset.?) {
        return error.BatchAlias;
    }
    if (contract.batch_count) |count| {
        if (count > 1 and contract.batch_lengths.len != count) return error.BatchAlias;
    }
}

fn validate_extra(route: facts.RouteFrameFacts, contract: producer_contract.ProducerContract) MapError!void {
    for (route.ownership, 0..) |entry, index| {
        for (route.ownership[0..index]) |prior| {
            if (prior.state_offset == entry.state_offset) return error.OwnershipStateOverlap;
        }
    }

    for (route.markers, 0..) |marker, index| {
        if (marker.name.len == 0) return error.InvalidMarker;
        if (marker.expected_value) |value| if (value.len == 0) return error.InvalidMarker;
        for (route.markers[0..index]) |prior| {
            if (std.mem.eql(u8, prior.name, marker.name)) return error.InvalidMarker;
        }
    }

    for (route.lifecycle) |anchor| {
        if (anchor.name.len == 0 or anchor.required_text.len == 0 or anchor.ordered_anchors.len == 0) {
            return error.InvalidLifecycle;
        }
        if (anchor.required_text.len != anchor.ordered_anchors.len) return error.InvalidLifecycle;
        for (anchor.required_text, 0..) |required, index| {
            if (required.len == 0 or contains(anchor.required_text[0..index], required)) return error.InvalidLifecycle;
            if (!contains(anchor.ordered_anchors, required)) return error.InvalidLifecycle;
        }
        for (anchor.ordered_anchors) |ordered| {
            if (ordered.len == 0 or !contains(anchor.required_text, ordered)) return error.InvalidLifecycle;
        }
        for (anchor.ordered_anchors, 0..) |ordered, index| {
            if (contains(anchor.ordered_anchors[0..index], ordered)) return error.InvalidLifecycle;
        }
    }

    try validate_bounds_and_alias(route, contract);
}

fn contains(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, needle)) return true;
    return false;
}

fn map_fact_error(err: facts.FactError) MapError {
    return switch (err) {
        error.InvalidIdentity => error.InvalidIdentity,
        error.FrameOverlap, error.FrameOutside, error.FrameMisaligned, error.InvalidFrameSize => error.InvalidFrame,
        error.InvalidFrame => error.InvalidFrame,
        error.InvalidOwnership, error.OwnershipStateOutsideFrame => error.InvalidFacts,
        error.InvalidBinding => error.InvalidBinding,
        error.BindingOutsidePayload, error.BindingOutsideFrame => error.InvalidBinding,
        error.BindingOverlap => error.BindingOverlap,
        error.MissingLifecycle => error.InvalidLifecycle,
    };
}
