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
    OwnershipStateRoleMismatch,
    BindingTopologyMismatch,
    OwnershipTopologyMismatch,
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

pub const AssetKind = enum { resource, list_backing };
pub const AssetDisposition = enum { transfer_to_host, release_after_copy };
pub const AssetId = struct { group_index: u32, asset_index: u32 };
pub const LifecycleAsset = struct { id: AssetId, kind: AssetKind, disposition: AssetDisposition, path: []const []const u8 };
pub const LifecycleGroup = struct { group_index: u32, asset_start: u32, asset_count: u32 };
pub const AtomicGroupTransfer = struct { group_index: u32, asset_start: u32, asset_count: u32 };
pub const CancelPlan = struct { pre_transfer_state: []const u8, post_transfer_state: []const u8, rolls_back_host_effects: bool };
pub const TerminalPlan = struct { close_action: []const u8, abort_action: ?[]const u8, cancel_action: []const u8 };

pub const LifecycleStateIR = struct {
    assets: [64]LifecycleAsset,
    asset_count: u32,
    groups: [64]LifecycleGroup,
    group_count: u32,
    acquire_order: [64]AssetId,
    acquire_count: u32,
    complete_write_barrier: [64]u32,
    barrier_count: u32,
    transfer_commit: [64]AtomicGroupTransfer,
    transfer_count: u32,
    post_transfer_cancel: CancelPlan,
    reverse_release: [64]AssetId,
    reverse_release_count: u32,
    cleanup_order: [7]producer_contract.CleanupStage,
    cleanup_count: u32,
    lifecycle_anchors: []const facts.LifecycleAnchor,
    terminal: TerminalPlan,
};

pub const LifecycleError = error{
    InvalidGroup,
    InvalidAsset,
    UnsupportedBound,
    TransferBeforeCompleteWrite,
    PartialGroupTransfer,
    InvalidDisposition,
    InvalidReverseRelease,
    CleanupOrderMismatch,
    DuplicateCleanupStage,
    ParentCleanupBeforeChild,
    PostTransferRollback,
    TerminalBeforeCleanup,
};

comptime {
    if (@typeInfo(producer_contract.CleanupStage).@"enum".fields.len != 7) {
        @compileError("LifecycleStateIR cleanup capacity must match CleanupStage");
    }
}

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
    try validate_fact_contract_correspondence(input.frame_facts, input.contract);

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
    try validate_fact_contract_correspondence(route_facts, contract);
}

pub fn build_lifecycle_ir(contract: producer_contract.ProducerContract, map: CanonicalFrameMap) LifecycleError!LifecycleStateIR {
    validate_contract_for_lifecycle(contract) catch |err| return err;
    validate_map_for_lifecycle(contract, map) catch |err| return err;
    const group_count = try lifecycle_group_count(contract, map);
    const schema_count = try lifecycle_schema_count(contract);
    const asset_count = std.math.mul(u32, group_count, schema_count) catch return error.UnsupportedBound;
    if (asset_count == 0) return error.InvalidAsset;
    if (asset_count > 64) return error.UnsupportedBound;

    var ir = LifecycleStateIR{
        .assets = undefined,
        .asset_count = asset_count,
        .groups = undefined,
        .group_count = group_count,
        .acquire_order = undefined,
        .acquire_count = asset_count,
        .complete_write_barrier = undefined,
        .barrier_count = group_count,
        .transfer_commit = undefined,
        .transfer_count = group_count,
        .post_transfer_cancel = .{
            .pre_transfer_state = "active",
            .post_transfer_state = "cancel_requested",
            .rolls_back_host_effects = false,
        },
        .reverse_release = undefined,
        .reverse_release_count = asset_count,
        .cleanup_order = undefined,
        .cleanup_count = @intCast(contract.terminal.cleanup_order.len),
        .lifecycle_anchors = map.lifecycle,
        .terminal = .{
            .close_action = contract.terminal.close_action,
            .abort_action = contract.terminal.abort_action,
            .cancel_action = contract.terminal.cancel_action,
        },
    };

    for (0..@intCast(group_count)) |group_index| {
        const group = @as(u32, @intCast(group_index));
        const start = group * schema_count;
        ir.groups[group_index] = .{ .group_index = group, .asset_start = start, .asset_count = schema_count };
        ir.complete_write_barrier[group_index] = group;
        ir.transfer_commit[group_index] = .{ .group_index = group, .asset_start = start, .asset_count = schema_count };
        for (0..@intCast(schema_count)) |asset_index| {
            const local = @as(u32, @intCast(asset_index));
            const global = @as(usize, @intCast(start + local));
            ir.assets[global] = try expected_asset(contract, local, group);
            ir.acquire_order[global] = .{ .group_index = group, .asset_index = local };
            ir.reverse_release[global] = .{
                .group_index = group_count - 1 - group,
                .asset_index = schema_count - 1 - local,
            };
        }
    }
    for (contract.terminal.cleanup_order, 0..) |stage, index| ir.cleanup_order[index] = stage;

    validate_lifecycle_ir(contract, map, ir) catch |err| return err;
    return ir;
}

pub fn validate_lifecycle_ir(contract: producer_contract.ProducerContract, map: CanonicalFrameMap, ir: LifecycleStateIR) LifecycleError!void {
    validate_contract_for_lifecycle(contract) catch |err| return err;
    validate_map_for_lifecycle(contract, map) catch |err| return err;
    const group_count = try lifecycle_group_count(contract, map);
    const schema_count = try lifecycle_schema_count(contract);
    const expected_asset_count = std.math.mul(u32, group_count, schema_count) catch return error.UnsupportedBound;
    if (ir.group_count != group_count or ir.group_count == 0 or ir.group_count > 64) return error.InvalidGroup;
    if (ir.asset_count != expected_asset_count or ir.asset_count == 0 or ir.asset_count > 64) return error.InvalidAsset;
    if (ir.asset_count != ir.acquire_count or ir.asset_count != ir.reverse_release_count) return error.InvalidAsset;
    if (ir.group_count != ir.transfer_count) return error.InvalidGroup;
    if (ir.group_count != ir.barrier_count) return error.TransferBeforeCompleteWrite;
    if (ir.lifecycle_anchors.len != map.lifecycle.len or ir.lifecycle_anchors.len == 0) return error.InvalidAsset;
    for (ir.lifecycle_anchors, map.lifecycle) |actual, expected| {
        if (!std.mem.eql(u8, actual.name, expected.name) or
            !string_lists_equal(actual.required_text, expected.required_text) or
            !string_lists_equal(actual.ordered_anchors, expected.ordered_anchors)) return error.InvalidAsset;
    }

    for (0..@intCast(ir.group_count)) |index| {
        const group = @as(u32, @intCast(index));
        const start = group * schema_count;
        const range = ir.groups[index];
        if (range.group_index != group or range.asset_start != start or range.asset_count != schema_count) {
            return error.InvalidGroup;
        }
        if (ir.complete_write_barrier[index] != group) return error.TransferBeforeCompleteWrite;
        const transfer = ir.transfer_commit[index];
        if (transfer.group_index != group) return error.TransferBeforeCompleteWrite;
        if (transfer.asset_start != start or transfer.asset_count != schema_count) return error.PartialGroupTransfer;
        for (0..@intCast(schema_count)) |local_index| {
            const local = @as(u32, @intCast(local_index));
            const global = @as(usize, @intCast(start + local));
            const asset = ir.assets[global];
            const expected = try expected_asset(contract, local, group);
            if (asset.id.group_index != group or asset.id.asset_index != local) return error.InvalidAsset;
            if (asset.kind != expected.kind or !same_path(asset.path, expected.path)) {
                return error.InvalidAsset;
            }
            if (!valid_disposition(asset)) return error.InvalidDisposition;
        }
    }

    for (0..@intCast(ir.asset_count)) |index| {
        const expected = ir.acquire_order[index];
        const reverse_index = ir.asset_count - 1 - @as(u32, @intCast(index));
        const expected_group = @as(u32, @intCast(index)) / schema_count;
        const expected_local = @as(u32, @intCast(index)) % schema_count;
        if (expected.group_index != expected_group or expected.asset_index != expected_local) return error.InvalidAsset;
        if (!same_asset_id(ir.reverse_release[index], ir.acquire_order[@intCast(reverse_index)])) {
            return error.InvalidReverseRelease;
        }
        if (expected.group_index >= ir.group_count or expected.asset_index >= schema_count) return error.InvalidAsset;
    }

    if (!std.mem.eql(u8, ir.post_transfer_cancel.pre_transfer_state, "active") or
        !std.mem.eql(u8, ir.post_transfer_cancel.post_transfer_state, "cancel_requested"))
    {
        return error.PostTransferRollback;
    }
    if (ir.post_transfer_cancel.rolls_back_host_effects) return error.PostTransferRollback;

    if (ir.cleanup_count > 7) return error.CleanupOrderMismatch;
    var seen = [_]bool{false} ** 7;
    var previous: ?u8 = null;
    for (0..@intCast(ir.cleanup_count)) |index| {
        const stage = ir.cleanup_order[index];
        const ordinal = @intFromEnum(stage);
        if (seen[ordinal]) return error.DuplicateCleanupStage;
        seen[ordinal] = true;
        if (previous) |prior| if (ordinal < prior) return error.ParentCleanupBeforeChild;
        previous = ordinal;
    }
    if (ir.cleanup_count != contract.terminal.cleanup_order.len) return error.TerminalBeforeCleanup;
    for (contract.terminal.cleanup_order, 0..) |stage, index| {
        if (ir.cleanup_order[index] != stage) return error.CleanupOrderMismatch;
    }
    if (!std.mem.eql(u8, ir.terminal.close_action, contract.terminal.close_action) or
        !std.mem.eql(u8, ir.terminal.cancel_action, contract.terminal.cancel_action) or
        !same_optional(ir.terminal.abort_action, contract.terminal.abort_action))
    {
        return error.TerminalBeforeCleanup;
    }
}

fn lifecycle_group_count(contract: producer_contract.ProducerContract, map: CanonicalFrameMap) LifecycleError!u32 {
    if (map.route_id.len == 0 or map.descriptor_id.len == 0 or
        !std.mem.eql(u8, map.descriptor_id, contract.descriptor_id)) return error.InvalidGroup;
    if (map.frame_size != 128) return error.UnsupportedBound;
    if (map.ownership.len > 64) return error.UnsupportedBound;
    if (contract.batch_count) |batch_count| {
        if (batch_count == 0 or batch_count > 64) return error.UnsupportedBound;
        if (map.ownership.len != batch_count) return error.InvalidGroup;
        return batch_count;
    }
    if (map.ownership.len == 0) {
        if (contract.ownership.leaves.len != 0) return error.InvalidGroup;
        return 1;
    }
    if (map.ownership.len != 1) return error.InvalidGroup;
    return 1;
}

fn validate_map_for_lifecycle(contract: producer_contract.ProducerContract, map: CanonicalFrameMap) LifecycleError!void {
    validate_frame_map(map, contract) catch |err| switch (err) {
        error.InvalidIdentity => return error.InvalidGroup,
        error.UnsupportedBound => return error.UnsupportedBound,
        error.BatchAlias => return error.InvalidGroup,
        else => return error.InvalidAsset,
    };
}

fn lifecycle_schema_count(contract: producer_contract.ProducerContract) LifecycleError!u32 {
    var count: u32 = @intCast(contract.ownership.leaves.len);
    count = std.math.add(u32, count, @intCast(contract.list_allocations.len)) catch return error.UnsupportedBound;
    switch (contract.payload) {
        .list => |layout| {
            var covered = false;
            for (contract.list_allocations) |allocation| {
                if (allocation.pointer_offset == layout.pointer_offset and allocation.length_offset == layout.length_offset and
                    allocation.element_stride == layout.element_stride and allocation.max_items == layout.max_items)
                {
                    covered = true;
                    break;
                }
            }
            if (!covered) count = std.math.add(u32, count, 1) catch return error.UnsupportedBound;
        },
        else => {},
    }
    if (count == 0) return error.InvalidAsset;
    if (count > 64) return error.UnsupportedBound;
    return count;
}

fn expected_asset(contract: producer_contract.ProducerContract, index: u32, group: u32) LifecycleError!LifecycleAsset {
    const leaf_count: u32 = @intCast(contract.ownership.leaves.len);
    if (index < leaf_count) return .{ .id = .{ .group_index = group, .asset_index = index }, .kind = .resource, .disposition = .transfer_to_host, .path = contract.ownership.leaves[index].path };
    var remaining = index - leaf_count;
    if (remaining < contract.list_allocations.len) return .{ .id = .{ .group_index = group, .asset_index = index }, .kind = .list_backing, .disposition = .release_after_copy, .path = contract.list_allocations[remaining].path };
    remaining -= @intCast(contract.list_allocations.len);
    switch (contract.payload) {
        .list => |layout| {
            if (remaining == 0) {
                var covered = false;
                for (contract.list_allocations) |allocation| {
                    if (allocation.pointer_offset == layout.pointer_offset and allocation.length_offset == layout.length_offset and
                        allocation.element_stride == layout.element_stride and allocation.max_items == layout.max_items)
                    {
                        covered = true;
                        break;
                    }
                }
                if (!covered) return .{ .id = .{ .group_index = group, .asset_index = index }, .kind = .list_backing, .disposition = .release_after_copy, .path = &.{} };
            }
        },
        else => {},
    }
    return error.InvalidAsset;
}

fn validate_contract_for_lifecycle(contract: producer_contract.ProducerContract) LifecycleError!void {
    producer_contract.validate_contract(contract) catch |err| switch (err) {
        error.TransferBeforeCompleteWrite => return error.TransferBeforeCompleteWrite,
        error.NonReverseOwnershipCleanup => return error.InvalidReverseRelease,
        error.DuplicateCleanupStage => return error.DuplicateCleanupStage,
        error.ParentCleanupBeforeChild => return error.ParentCleanupBeforeChild,
        error.InvalidCleanupOrder => return error.CleanupOrderMismatch,
        error.InvalidListAllocation, error.DuplicateListAllocationPath, error.ListAllocationOwnershipOverlap => return error.InvalidAsset,
        else => return error.InvalidAsset,
    };
}

fn valid_disposition(asset: LifecycleAsset) bool {
    return (asset.kind == .resource and asset.disposition == .transfer_to_host) or
        (asset.kind == .list_backing and asset.disposition == .release_after_copy);
}

fn same_asset_id(left: AssetId, right: AssetId) bool {
    return left.group_index == right.group_index and left.asset_index == right.asset_index;
}

fn same_path(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_segment, right_segment| {
        if (!std.mem.eql(u8, left_segment, right_segment)) return false;
    }
    return true;
}

fn same_optional(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn string_lists_equal(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.mem.eql(u8, a, b)) return false;
    return true;
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

fn validate_fact_contract_correspondence(route: facts.RouteFrameFacts, contract: producer_contract.ProducerContract) MapError!void {
    for (route.ownership) |ownership| {
        var matched_state = false;
        for (route.frames) |field| {
            if (field.role == .ownership_state and field.offset == ownership.state_offset and field.width >= 4) {
                matched_state = true;
                break;
            }
        }
        if (!matched_state) return error.OwnershipStateRoleMismatch;
    }

    switch (contract.payload) {
        .record => |layout| try validate_record_fact_topology(route, contract, layout),
        else => {},
    }
}

fn validate_record_fact_topology(
    route: facts.RouteFrameFacts,
    contract: producer_contract.ProducerContract,
    layout: anytype,
) MapError!void {
    if (route.bindings.len != layout.fields.len) return error.BindingTopologyMismatch;
    if (route.ownership.len != contract.ownership.leaves.len) return error.OwnershipTopologyMismatch;

    for (layout.fields, 0..) |field, field_index| {
        const binding = find_binding(route.bindings, field.name) orelse return error.BindingTopologyMismatch;
        const width = record_field_width(layout, field_index);
        if (binding.canonical_offset != field.offset or binding.payload_size != layout.byte_size or
            binding.width != width) return error.BindingTopologyMismatch;
        var frame_match = false;
        for (route.frames) |frame| {
            if (frame.offset == binding.frame_offset and frame.width >= binding.width) {
                frame_match = true;
                break;
            }
        }
        if (!frame_match) return error.BindingTopologyMismatch;

        if (find_source_field(layout.source_fields, field.name)) |source| {
            if (source.ownership == .own and !frame_has_resource_handle(route.frames, binding.frame_offset, binding.width)) {
                return error.BindingTopologyMismatch;
            }
        }
    }

    for (contract.ownership.leaves) |leaf| {
        const name = leaf.path[leaf.path.len - 1];
        const source = find_source_field(layout.source_fields, name) orelse return error.OwnershipTopologyMismatch;
        if (source.ownership != .own or source.resource == null or !std.mem.eql(u8, source.resource.?, leaf.resource) or
            source.drop_import == null or !std.mem.eql(u8, source.drop_import.?, leaf.drop_import))
        {
            return error.OwnershipTopologyMismatch;
        }
        const binding = find_binding(route.bindings, name) orelse return error.OwnershipTopologyMismatch;
        const field = find_record_field(layout.fields, name) orelse return error.OwnershipTopologyMismatch;
        if (leaf.handle_offset != field.offset) return error.OwnershipTopologyMismatch;
        if (!frame_has_resource_handle(route.frames, binding.frame_offset, binding.width)) {
            return error.OwnershipTopologyMismatch;
        }
    }
}

fn find_binding(bindings: []const facts.CanonicalBinding, name: []const u8) ?facts.CanonicalBinding {
    for (bindings) |binding| if (std.mem.eql(u8, binding.name, name)) return binding;
    return null;
}

fn find_record_field(fields: anytype, name: []const u8) ?@TypeOf(fields[0]) {
    for (fields) |field| if (std.mem.eql(u8, field.name, name)) return field;
    return null;
}

fn find_source_field(fields: anytype, name: []const u8) ?@TypeOf(fields[0]) {
    for (fields) |field| if (std.mem.eql(u8, field.name, name)) return field;
    return null;
}

fn record_field_width(layout: anytype, index: usize) u32 {
    const start = layout.fields[index].offset;
    var end = layout.byte_size;
    for (layout.fields) |field| {
        if (field.offset > start and field.offset < end) end = field.offset;
    }
    return end - start;
}

fn frame_has_resource_handle(frames: []const facts.FrameFact, offset: u32, width: u32) bool {
    for (frames) |frame| {
        if (frame.role == .resource_handle and frame.offset == offset and frame.width >= width) return true;
    }
    return false;
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
