const std = @import("std");
const producer_contract = @import("codegen_component_producer_contract.zig");

/// The audit describes measured facts in an existing Core-WAT producer
/// template. It deliberately has no emitter or route-dispatch behavior.
pub const AuditError = error{
    InvalidRouteId,
    InvalidFrameSize,
    InvalidRuntimeField,
    OffsetOutsideFrame,
    MisalignedOffset,
    RuntimeOffsetOverlap,
    DuplicateStateValue,
    MissingStateValue,
    InvalidControlState,
    DuplicateControlState,
    UncoveredPostTransferCancelState,
    InvalidCleanupOrder,
    DuplicateCleanupStage,
    MissingCleanupSymbol,
    UnknownCleanupOffset,
    InvalidBinding,
    CanonicalOffsetOutsidePayload,
    FrameOffsetOutsideFrame,
    CleanupStageMismatch,
    InvalidContract,
    MissingTemplateFragment,
    ForbiddenTemplateFragment,
    TemplateFragmentOrder,
};

pub const FieldRole = enum {
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

pub const RuntimeField = struct {
    name: []const u8,
    offset: u32,
    width: u32,
    alignment: u32,
    role: FieldRole = .payload,
};

pub const StateKind = enum {
    guest_owned,
    transferred,
    released,
};

pub const OwnershipState = struct {
    name: []const u8,
    value: u32,
    kind: StateKind,
};

pub const ControlState = struct {
    name: []const u8,
    value: u32,
};

pub const CanonicalBinding = struct {
    name: []const u8,
    canonical_offset: u32,
    payload_size: u32,
    frame_offset: u32,
    width: u32,
};

pub const CleanupStep = struct {
    stage: producer_contract.CleanupStage,
    symbol: []const u8,
    offsets: []const u32,
};

pub const RuntimeAudit = struct {
    route_id: []const u8,
    frame_size: u32,
    fields: []const RuntimeField,
    ownership_states: []const OwnershipState,
    control_states: []const ControlState,
    post_transfer_cancel_states: []const u32,
    bindings: []const CanonicalBinding,
    cleanup_steps: []const CleanupStep,
};

pub const AuditReport = struct {
    route_id: []const u8,
    frame_size: u32,
    field_count: usize,
    cleanup_count: usize,
    binding_count: usize,
    post_transfer_cancel_count: usize,
};

pub const TemplateAuditSpec = struct {
    route_id: []const u8,
    required_fragments: []const []const u8,
    ordered_fragments: []const []const u8,
    required_markers: []const []const u8,
    forbidden_fragments: []const []const u8,
};

pub fn validate(runtime: RuntimeAudit) AuditError!AuditReport {
    if (runtime.route_id.len == 0) return error.InvalidRouteId;
    if (runtime.frame_size == 0) return error.InvalidFrameSize;

    try validate_fields(runtime);
    try validate_ownership_states(runtime.ownership_states);
    try validate_control_states(runtime.control_states, runtime.post_transfer_cancel_states);
    try validate_bindings(runtime);
    try validate_cleanup(runtime);

    return .{
        .route_id = runtime.route_id,
        .frame_size = runtime.frame_size,
        .field_count = runtime.fields.len,
        .cleanup_count = runtime.cleanup_steps.len,
        .binding_count = runtime.bindings.len,
        .post_transfer_cancel_count = runtime.post_transfer_cancel_states.len,
    };
}

/// Validates the normalized contract and then checks that the measured
/// template exposes the same terminal cleanup stages in the same order.
/// This is an audit-only boundary; it does not emit or rewrite WAT.
pub fn validate_contract(
    contract: producer_contract.ProducerContract,
    runtime: RuntimeAudit,
) AuditError!AuditReport {
    producer_contract.validate_contract(contract) catch return error.InvalidContract;
    const report = try validate(runtime);

    if (contract.terminal.cleanup_order.len != runtime.cleanup_steps.len) {
        return error.CleanupStageMismatch;
    }
    for (contract.terminal.cleanup_order, runtime.cleanup_steps) |expected, actual| {
        if (expected != actual.stage) return error.CleanupStageMismatch;
    }
    return report;
}

/// Checks only the immutable text already present in a canonical template.
/// It never rewrites, parses, or emits WAT.
pub fn audit_template(template: []const u8, spec: TemplateAuditSpec) AuditError!void {
    if (spec.route_id.len == 0 or template.len == 0) return error.InvalidRouteId;

    for (spec.required_fragments) |fragment| {
        if (fragment.len == 0 or std.mem.indexOf(u8, template, fragment) == null) {
            return error.MissingTemplateFragment;
        }
    }
    for (spec.required_markers) |marker| {
        if (marker.len == 0 or std.mem.indexOf(u8, template, marker) == null) {
            return error.MissingTemplateFragment;
        }
    }
    for (spec.forbidden_fragments) |fragment| {
        if (fragment.len != 0 and std.mem.indexOf(u8, template, fragment) != null) {
            return error.ForbiddenTemplateFragment;
        }
    }

    var cursor: usize = 0;
    for (spec.ordered_fragments) |fragment| {
        if (fragment.len == 0) return error.MissingTemplateFragment;
        const relative = std.mem.indexOf(u8, template[cursor..], fragment) orelse
            return error.TemplateFragmentOrder;
        cursor += relative + fragment.len;
    }
}

fn validate_fields(runtime: RuntimeAudit) AuditError!void {
    for (runtime.fields, 0..) |field, index| {
        if (field.name.len == 0 or field.width == 0 or field.alignment == 0) {
            return error.InvalidRuntimeField;
        }
        if (field.offset % field.alignment != 0) return error.MisalignedOffset;
        try validate_range(runtime.frame_size, field.offset, field.width, error.OffsetOutsideFrame);

        for (runtime.fields[0..index]) |prior| {
            if (ranges_overlap(prior.offset, prior.width, field.offset, field.width)) {
                return error.RuntimeOffsetOverlap;
            }
        }
    }
}

fn validate_ownership_states(states: []const OwnershipState) AuditError!void {
    var seen_kinds = [_]bool{false} ** @typeInfo(StateKind).@"enum".fields.len;
    for (states, 0..) |state, index| {
        if (state.name.len == 0) return error.InvalidRuntimeField;
        const kind_index = @intFromEnum(state.kind);
        if (seen_kinds[kind_index]) return error.DuplicateStateValue;
        seen_kinds[kind_index] = true;
        for (states[0..index]) |prior| {
            if (prior.value == state.value) return error.DuplicateStateValue;
        }
    }
    for (seen_kinds) |seen| {
        if (!seen) return error.MissingStateValue;
    }
}

fn validate_control_states(
    states: []const ControlState,
    post_transfer_cancel_states: []const u32,
) AuditError!void {
    for (states, 0..) |state, index| {
        if (state.name.len == 0) return error.InvalidControlState;
        for (states[0..index]) |prior| {
            if (prior.value == state.value) return error.DuplicateControlState;
        }
    }
    for (post_transfer_cancel_states, 0..) |value, index| {
        for (post_transfer_cancel_states[0..index]) |prior| {
            if (prior == value) return error.DuplicateControlState;
        }
        if (!contains_control_state(states, value)) {
            return error.UncoveredPostTransferCancelState;
        }
    }
}

fn validate_bindings(runtime: RuntimeAudit) AuditError!void {
    for (runtime.bindings) |binding| {
        if (binding.name.len == 0 or binding.width == 0 or binding.payload_size == 0) {
            return error.InvalidBinding;
        }
        if (binding.canonical_offset > binding.payload_size or
            binding.width > binding.payload_size - binding.canonical_offset)
        {
            return error.CanonicalOffsetOutsidePayload;
        }
        validate_range(runtime.frame_size, binding.frame_offset, binding.width, error.FrameOffsetOutsideFrame) catch |err| {
            return err;
        };
    }
}

fn validate_cleanup(runtime: RuntimeAudit) AuditError!void {
    if (runtime.cleanup_steps.len == 0) return error.InvalidCleanupOrder;

    var seen = [_]bool{false} ** @typeInfo(producer_contract.CleanupStage).@"enum".fields.len;
    var previous: ?u8 = null;
    for (runtime.cleanup_steps) |step| {
        if (step.symbol.len == 0) return error.MissingCleanupSymbol;
        const ordinal = @intFromEnum(step.stage);
        if (seen[ordinal]) return error.DuplicateCleanupStage;
        seen[ordinal] = true;
        if (previous) |prior| {
            if (ordinal < prior) return error.InvalidCleanupOrder;
        }
        previous = ordinal;
        for (step.offsets) |offset| {
            if (!has_field_at(runtime.fields, offset)) return error.UnknownCleanupOffset;
        }
    }
}

fn validate_range(
    frame_size: u32,
    offset: u32,
    width: u32,
    comptime failure: AuditError,
) AuditError!void {
    if (width == 0 or offset > frame_size or width > frame_size - offset) return failure;
}

fn ranges_overlap(left_offset: u32, left_width: u32, right_offset: u32, right_width: u32) bool {
    return left_offset < right_offset + right_width and right_offset < left_offset + left_width;
}

fn has_field_at(fields: []const RuntimeField, offset: u32) bool {
    for (fields) |field| {
        if (field.offset == offset) return true;
    }
    return false;
}

fn contains_control_state(states: []const ControlState, value: u32) bool {
    for (states) |state| {
        if (state.value == value) return true;
    }
    return false;
}
