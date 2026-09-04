const std = @import("std");
const p3_async_manifest = @import("p3_async_manifest.zig");

/// This module contains the immutable facts shared by the private producer
/// emitters. Slices borrow the descriptor/lexer storage owned by the caller;
/// the contract never mutates or reallocates that storage.
pub const ContractError = error{
    InvalidContract,
    InvalidSourceContract,
    InvalidSinkContract,
    InvalidPayloadLayout,
    InvalidOwnershipPath,
    InvalidOwnershipParent,
    DuplicateOwnershipBit,
    DuplicateOwnershipPath,
    ZeroHandleAbsenceSentinel,
    MissingDropImport,
    TransferBeforeCompleteWrite,
    NonReverseOwnershipCleanup,
    InvalidCleanupOrder,
    DuplicateCleanupStage,
    ParentCleanupBeforeChild,
    UnsupportedProducerContract,
};

pub const SourceContract = struct {
    module: []const u8,
    import_name: []const u8,
    core_params: []const []const u8,
    core_results: []const []const u8,
};

pub const SinkContract = struct {
    module: []const u8,
    member: []const u8,
    capacity: u32,
    read_import: []const u8,
    write_import: []const u8,
    drop_import: []const u8,
};

pub const ScalarLayout = struct {
    core_type: []const u8,
    byte_size: u32,
    alignment: u32,
};

pub const ListLayout = struct {
    pointer_offset: u32,
    length_offset: u32,
    element_stride: u32,
    max_items: u32,
};

pub const PayloadLayout = union(enum) {
    scalar: ScalarLayout,
    record: p3_async_manifest.RecordLayout,
    list: ListLayout,
};

pub const OwnershipLeaf = struct {
    path: []const []const u8,
    resource: []const u8,
    handle_offset: u32,
    drop_import: []const u8,
    bit: u8,
    /// A non-null zero value is explicitly forbidden. The handle value zero
    /// is a valid Component resource-table handle, never an absence marker.
    absence_sentinel: ?u32 = null,
};

pub const OwnershipParent = struct {
    path: []const []const u8,
    bit: u8,
};

pub const OwnershipTransferPlan = struct {
    leaves: []const OwnershipLeaf,
    parents: []const OwnershipParent,
    complete_write_required: bool = true,
    pre_transfer_reverse_order: bool = true,
};

pub const CleanupStage = enum {
    resource,
    list,
    stream,
    future,
    subtask,
    waitable,
    frame,
};

pub const TerminalContract = struct {
    close_action: []const u8,
    abort_action: ?[]const u8,
    cancel_action: []const u8,
    cleanup_order: []const CleanupStage,
};

pub const ProducerContract = struct {
    descriptor_id: []const u8,
    /// The registry hash is carried through the normalized plan so a caller
    /// cannot accidentally pair measured layout with a different WIT.
    descriptor_hash: ?[]const u8 = null,
    source: SourceContract,
    sink: SinkContract,
    payload: PayloadLayout,
    ownership: OwnershipTransferPlan,
    terminal: TerminalContract,
    runtime_count_param: ?[]const u8 = null,
    runtime_max: ?u32 = null,
    runtime_mode_param: ?[]const u8 = null,
    batch_count: ?u32 = null,
    batch_lengths: []const u32 = &.{},
    producer_core_params: []const []const u8 = &.{},
    producer_core_results: []const []const u8 = &.{},
    left_seed_param: ?[]const u8 = null,
    right_seed_param: ?[]const u8 = null,
};

pub fn validate_contract(value: ProducerContract) ContractError!void {
    if (value.descriptor_id.len == 0) return error.InvalidContract;
    if (value.descriptor_hash) |hash| {
        if (hash.len == 0) return error.InvalidContract;
    }
    if (value.source.module.len == 0 or value.source.import_name.len == 0) {
        return error.InvalidSourceContract;
    }
    if (value.sink.module.len == 0 or value.sink.member.len == 0 or
        value.sink.read_import.len == 0 or value.sink.write_import.len == 0 or
        value.sink.drop_import.len == 0)
    {
        return error.InvalidSinkContract;
    }

    switch (value.payload) {
        .scalar => |layout| {
            if (layout.core_type.len == 0 or layout.byte_size == 0 or layout.alignment == 0) {
                return error.InvalidPayloadLayout;
            }
        },
        .record => |layout| {
            if (layout.name.len == 0 or layout.byte_size == 0) return error.InvalidPayloadLayout;
            for (layout.fields) |field| {
                if (field.name.len == 0 or field.core_type.len == 0 or field.offset >= layout.byte_size) {
                    return error.InvalidPayloadLayout;
                }
            }
        },
        .list => |layout| {
            if (layout.pointer_offset == 0 or layout.length_offset == 0 or
                layout.pointer_offset == layout.length_offset or layout.element_stride == 0 or
                layout.max_items == 0) return error.InvalidPayloadLayout;
        },
    }

    if (!value.ownership.complete_write_required) return error.TransferBeforeCompleteWrite;
    if (!value.ownership.pre_transfer_reverse_order) return error.NonReverseOwnershipCleanup;
    try validate_ownership(value.ownership);
    try validate_terminal(value.terminal);
}

fn validate_ownership(ownership: OwnershipTransferPlan) ContractError!void {
    for (ownership.leaves, 0..) |leaf, index| {
        if (leaf.path.len == 0) return error.InvalidOwnershipPath;
        if (leaf.resource.len == 0) return error.InvalidContract;
        if (leaf.drop_import.len == 0) return error.MissingDropImport;
        if (leaf.absence_sentinel) |sentinel| {
            if (sentinel == 0) return error.ZeroHandleAbsenceSentinel;
        }
        for (ownership.leaves[0..index]) |prior| {
            if (prior.bit == leaf.bit) return error.DuplicateOwnershipBit;
            if (same_path(prior.path, leaf.path)) return error.DuplicateOwnershipPath;
        }
        for (ownership.parents) |parent| {
            if (parent.bit == leaf.bit) return error.DuplicateOwnershipBit;
            if (same_path(parent.path, leaf.path)) return error.DuplicateOwnershipPath;
        }
    }

    for (ownership.parents, 0..) |parent, index| {
        if (parent.path.len == 0) return error.InvalidOwnershipParent;
        for (ownership.parents[0..index]) |prior| {
            if (prior.bit == parent.bit) return error.DuplicateOwnershipBit;
            if (same_path(prior.path, parent.path)) return error.DuplicateOwnershipPath;
        }
        var has_child = false;
        for (ownership.leaves) |leaf| {
            if (is_strict_prefix(parent.path, leaf.path)) {
                has_child = true;
                break;
            }
        }
        if (!has_child) return error.InvalidOwnershipParent;
    }
}

fn validate_terminal(terminal: TerminalContract) ContractError!void {
    if (terminal.close_action.len == 0 or terminal.cancel_action.len == 0 or terminal.cleanup_order.len == 0) {
        return error.InvalidCleanupOrder;
    }
    if (terminal.abort_action) |action| {
        if (action.len == 0) return error.InvalidCleanupOrder;
    }

    var seen = [_]bool{false} ** @typeInfo(CleanupStage).@"enum".fields.len;
    var previous_rank: u8 = 0;
    for (terminal.cleanup_order, 0..) |stage, index| {
        const ordinal = @intFromEnum(stage);
        if (seen[ordinal]) return error.DuplicateCleanupStage;
        seen[ordinal] = true;
        if (index != 0 and ordinal < previous_rank) return error.ParentCleanupBeforeChild;
        previous_rank = ordinal;
    }
}

fn same_path(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_segment, right_segment| {
        if (!std.mem.eql(u8, left_segment, right_segment)) return false;
    }
    return true;
}

fn is_strict_prefix(prefix: []const []const u8, path: []const []const u8) bool {
    if (prefix.len >= path.len) return false;
    for (prefix, path[0..prefix.len]) |prefix_segment, path_segment| {
        if (!std.mem.eql(u8, prefix_segment, path_segment)) return false;
    }
    return true;
}

const RecordProducerKind = enum {
    direct,
    pair,
    triple,
    nested,
    list,
    dynamic_list,
    batched_list,
};

const direct_ticket_path = [_][]const u8{"ticket"};
const pair_left_path = [_][]const u8{"left"};
const pair_right_path = [_][]const u8{"right"};
const triple_left_path = [_][]const u8{"left"};
const triple_middle_path = [_][]const u8{"middle"};
const triple_right_path = [_][]const u8{"right"};
const nested_inner_path = [_][]const u8{"inner"};
const nested_inner_ticket_path = [_][]const u8{ "inner", "ticket" };
const list_path = [_][]const u8{"list"};
const list_ticket_path = [_][]const u8{ "list", "ticket" };

// These arrays are intentionally module constants. The current producer
// registry admits only the named private layouts below, so conversion can
// borrow path storage without introducing an ownership/deinit obligation.
const direct_ticket_leaves = [_]OwnershipLeaf{
    .{ .path = &direct_ticket_path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
};
const pair_ticket_leaves = [_]OwnershipLeaf{
    .{ .path = &pair_left_path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
    .{ .path = &pair_right_path, .resource = "ticket", .handle_offset = 4, .drop_import = "[resource-drop]ticket", .bit = 1 },
};
const triple_ticket_leaves = [_]OwnershipLeaf{
    .{ .path = &triple_left_path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
    .{ .path = &triple_middle_path, .resource = "ticket", .handle_offset = 4, .drop_import = "[resource-drop]ticket", .bit = 1 },
    .{ .path = &triple_right_path, .resource = "ticket", .handle_offset = 8, .drop_import = "[resource-drop]ticket", .bit = 2 },
};
const nested_ticket_leaves = [_]OwnershipLeaf{
    .{ .path = &nested_inner_ticket_path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
};
const nested_ticket_parents = [_]OwnershipParent{
    .{ .path = &nested_inner_path, .bit = 1 },
};
const list_ticket_leaves = [_]OwnershipLeaf{
    .{ .path = &list_ticket_path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
};
const list_ticket_parents = [_]OwnershipParent{
    .{ .path = &list_path, .bit = 1 },
};

/// Convert one already-admitted manifest shape to the private normalized
/// contract. This function deliberately accepts the shape alongside its
/// descriptor so callers cannot use a neighboring descriptor's measured
/// layout. All returned slices borrow descriptor storage or the constants
/// above; callers release only the registry that owns descriptor storage.
pub fn producer_contract_from_shape(
    descriptor: p3_async_manifest.Descriptor,
    shape: p3_async_manifest.LoweringShape,
) ContractError!ProducerContract {
    if (descriptor.locator.len == 0 or descriptor.member.len == 0 or
        descriptor.wit_sha256 == null or descriptor.wit_sha256.?.len == 0)
        return error.UnsupportedProducerContract;

    return switch (shape) {
        .owned_record_stream_producer => |value| build_record_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.producer,
            value.stream,
            .direct,
        ),
        .record_resource_pair_stream_producer => |value| build_record_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.producer,
            value.stream,
            .pair,
        ),
        .record_resource_triple_stream_producer => |value| build_record_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.producer,
            value.stream,
            .triple,
        ),
        .record_resource_nested_stream_producer => |value| build_record_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.producer,
            value.stream,
            .nested,
        ),
        .record_resource_pair_parameterized_stream_producer => |value| build_parameterized_pair_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.producer,
            value.stream,
        ),
        .record_resource_list_stream_producer => |value| build_list_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.list_layout,
            value.producer,
            value.stream,
            .list,
        ),
        .record_resource_list_stream_dynamic_producer => |value| build_list_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.list_layout,
            value.producer,
            value.stream,
            .dynamic_list,
        ),
        .record_resource_list_stream_batched_producer => |value| build_list_contract(
            descriptor,
            value.element,
            value.record_layout,
            value.list_layout,
            value.producer,
            value.stream,
            .batched_list,
        ),
        .scalar_list_stream_producer => |value| build_scalar_list_contract(
            descriptor,
            value.element,
            value.list_layout,
            value.producer,
            value.stream,
        ),
        else => error.UnsupportedProducerContract,
    };
}

/// Resolve and convert a descriptor in one fail-closed operation. Callers that
/// already performed shape selection may use `producer_contract_from_shape`
/// directly to keep the measured shape visible at the adapter boundary.
pub fn producer_contract_from_descriptor(
    descriptor: p3_async_manifest.Descriptor,
) ContractError!ProducerContract {
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse
        return error.UnsupportedProducerContract;
    return producer_contract_from_shape(descriptor, shape);
}

fn build_record_contract(
    descriptor: p3_async_manifest.Descriptor,
    element: []const u8,
    layout: p3_async_manifest.RecordLayout,
    producer: p3_async_manifest.ProducerCanonical,
    stream: p3_async_manifest.StreamCanonical,
    kind: RecordProducerKind,
) ContractError!ProducerContract {
    if (!record_descriptor_matches(descriptor, element, producer, stream) or
        !record_effect_matches(descriptor, kind)) return error.UnsupportedProducerContract;

    const ownership = switch (kind) {
        .direct => try ownership_for_direct(layout),
        .pair => try ownership_for_pair(layout),
        .triple => try ownership_for_triple(layout),
        .nested => try ownership_for_nested(layout),
        else => return error.UnsupportedProducerContract,
    };
    const value = ProducerContract{
        .descriptor_id = descriptor.locator,
        .descriptor_hash = descriptor.wit_sha256,
        .source = source_from_producer(producer),
        .sink = sink_from_stream(descriptor, stream, producer.stream_capacity),
        .payload = .{ .record = layout },
        .ownership = ownership,
        .terminal = terminal_from_stream(producer.terminal, stream),
        .runtime_count_param = producer.runtime_count_param,
        .runtime_max = producer.runtime_max,
        .runtime_mode_param = producer.runtime_mode_param,
        .batch_count = producer.batch_count,
        .batch_lengths = producer.batch_lengths orelse &.{},
    };
    validate_contract(value) catch return error.UnsupportedProducerContract;
    return value;
}

fn build_parameterized_pair_contract(
    descriptor: p3_async_manifest.Descriptor,
    element: []const u8,
    layout: p3_async_manifest.RecordLayout,
    producer: p3_async_manifest.ParameterizedOwnedRecordPairProducerCanonical,
    stream: p3_async_manifest.StreamCanonical,
) ContractError!ProducerContract {
    if (!std.mem.eql(u8, descriptor.effect, "record-resource-pair-parameterized-stream-producer") or
        !std.mem.eql(u8, element, "resource-pair") or
        !record_descriptor_matches_common(descriptor, stream) or
        producer.stream_capacity == 0 or producer.source_module.len == 0 or
        producer.source_import_name.len == 0 or producer.resource_drop_import.len == 0 or
        producer.terminal.len == 0 or producer.runtime_mode_param.len == 0 or
        producer.left_seed_param.len == 0 or producer.right_seed_param.len == 0 or
        producer.producer_core_params.len == 0 or producer.producer_core_results.len == 0)
        return error.UnsupportedProducerContract;
    const ownership = try ownership_for_pair(layout);
    const value = ProducerContract{
        .descriptor_id = descriptor.locator,
        .descriptor_hash = descriptor.wit_sha256,
        .source = .{
            .module = producer.source_module,
            .import_name = producer.source_import_name,
            .core_params = producer.source_core_params,
            .core_results = producer.source_core_results,
        },
        .sink = sink_from_stream(descriptor, stream, producer.stream_capacity),
        .payload = .{ .record = layout },
        .ownership = ownership,
        .terminal = terminal_from_stream(producer.terminal, stream),
        .runtime_mode_param = producer.runtime_mode_param,
        .producer_core_params = producer.producer_core_params,
        .producer_core_results = producer.producer_core_results,
        .left_seed_param = producer.left_seed_param,
        .right_seed_param = producer.right_seed_param,
    };
    validate_contract(value) catch return error.UnsupportedProducerContract;
    return value;
}

fn build_list_contract(
    descriptor: p3_async_manifest.Descriptor,
    element: []const u8,
    record_layout: p3_async_manifest.RecordLayout,
    list_layout: p3_async_manifest.ListResourceLayout,
    producer: p3_async_manifest.ProducerCanonical,
    stream: p3_async_manifest.StreamCanonical,
    kind: RecordProducerKind,
) ContractError!ProducerContract {
    if (!producer_descriptor_matches(descriptor, stream) or
        !std.mem.eql(u8, stream.element, "list<resource-entry>") or
        !std.mem.eql(u8, element, "resource-entry") or
        !list_effect_matches(descriptor, kind) or
        !valid_owned_record_layout(record_layout, "resource-entry", &.{"ticket"}, &.{0}) or
        list_layout.result_pointer_offset == 0 or list_layout.result_length_offset == 0 or
        list_layout.element_stride == 0 or list_layout.max_items == 0 or
        list_layout.ticket_offset != 0) return error.UnsupportedProducerContract;
    if (kind == .list and (producer.runtime_count_param != null or producer.runtime_max != null or
        producer.runtime_mode_param != null or producer.batch_count != null or producer.batch_lengths != null))
        return error.UnsupportedProducerContract;
    if (kind == .dynamic_list and (producer.runtime_count_param == null or producer.runtime_max == null or
        producer.runtime_mode_param != null or producer.batch_count != null or producer.batch_lengths != null))
        return error.UnsupportedProducerContract;
    if (kind == .batched_list and (producer.runtime_count_param != null or producer.runtime_max != null or
        producer.runtime_mode_param == null or producer.batch_count == null or producer.batch_lengths == null))
        return error.UnsupportedProducerContract;

    const value = ProducerContract{
        .descriptor_id = descriptor.locator,
        .descriptor_hash = descriptor.wit_sha256,
        .source = source_from_producer(producer),
        .sink = sink_from_stream(descriptor, stream, producer.stream_capacity),
        .payload = .{ .list = .{
            .pointer_offset = list_layout.result_pointer_offset,
            .length_offset = list_layout.result_length_offset,
            .element_stride = list_layout.element_stride,
            .max_items = list_layout.max_items,
        } },
        .ownership = .{
            .leaves = &list_ticket_leaves,
            .parents = &list_ticket_parents,
        },
        .terminal = terminal_from_stream(producer.terminal, stream),
        .runtime_count_param = producer.runtime_count_param,
        .runtime_max = producer.runtime_max,
        .runtime_mode_param = producer.runtime_mode_param,
        .batch_count = producer.batch_count,
        .batch_lengths = producer.batch_lengths orelse &.{},
    };
    validate_contract(value) catch return error.UnsupportedProducerContract;
    return value;
}

fn build_scalar_list_contract(
    descriptor: p3_async_manifest.Descriptor,
    element: []const u8,
    list_layout: p3_async_manifest.ScalarListLayout,
    producer: p3_async_manifest.ScalarListProducerCanonical,
    stream: p3_async_manifest.StreamCanonical,
) ContractError!ProducerContract {
    if (!std.mem.eql(u8, descriptor.effect, "scalar-list-stream-producer") or
        !std.mem.eql(u8, element, "list<u32>") or
        !producer_descriptor_matches(descriptor, stream) or
        !std.mem.eql(u8, stream.element, element) or
        list_layout.result_pointer_offset == 0 or list_layout.result_length_offset == 0 or
        list_layout.element_stride == 0 or list_layout.max_items == 0 or
        producer.stream_capacity == 0 or producer.runtime_max == 0 or
        producer.runtime_count_param.len == 0) return error.UnsupportedProducerContract;

    const value = ProducerContract{
        .descriptor_id = descriptor.locator,
        .descriptor_hash = descriptor.wit_sha256,
        // Scalar-list producers have no separate make-ticket operation. The
        // descriptor's measured async operation is the only source fact.
        .source = .{
            .module = descriptor.canonical.async_import_module,
            .import_name = descriptor.canonical.async_import_name,
            .core_params = descriptor.canonical.core_params,
            .core_results = descriptor.canonical.core_results,
        },
        .sink = sink_from_stream(descriptor, stream, producer.stream_capacity),
        .payload = .{ .list = .{
            .pointer_offset = list_layout.result_pointer_offset,
            .length_offset = list_layout.result_length_offset,
            .element_stride = list_layout.element_stride,
            .max_items = list_layout.max_items,
        } },
        .ownership = .{ .leaves = &.{}, .parents = &.{} },
        .terminal = terminal_from_stream(producer.terminal, stream),
        .runtime_count_param = producer.runtime_count_param,
        .runtime_max = producer.runtime_max,
    };
    validate_contract(value) catch return error.UnsupportedProducerContract;
    return value;
}

fn record_descriptor_matches(
    descriptor: p3_async_manifest.Descriptor,
    element: []const u8,
    producer: p3_async_manifest.ProducerCanonical,
    stream: p3_async_manifest.StreamCanonical,
) bool {
    return producer_descriptor_matches(descriptor, stream) and
        std.mem.eql(u8, stream.element, element) and
        producer.stream_capacity != 0 and producer.source_module.len != 0 and
        producer.source_import_name.len != 0 and producer.resource_drop_import.len != 0 and
        producer.terminal.len != 0;
}

fn record_effect_matches(descriptor: p3_async_manifest.Descriptor, kind: RecordProducerKind) bool {
    return switch (kind) {
        .direct => std.mem.eql(u8, descriptor.effect, "record-resource-stream-producer"),
        .pair => std.mem.eql(u8, descriptor.effect, "record-resource-pair-stream-producer"),
        .triple => std.mem.eql(u8, descriptor.effect, "record-resource-triple-stream-producer"),
        .nested => std.mem.eql(u8, descriptor.effect, "record-resource-nested-stream-producer"),
        else => false,
    };
}

fn list_effect_matches(descriptor: p3_async_manifest.Descriptor, kind: RecordProducerKind) bool {
    return switch (kind) {
        .list => std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-producer"),
        .dynamic_list => std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-dynamic-producer"),
        .batched_list => std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-batched-producer"),
        else => false,
    };
}

fn record_descriptor_matches_common(
    descriptor: p3_async_manifest.Descriptor,
    stream: p3_async_manifest.StreamCanonical,
) bool {
    return producer_descriptor_matches(descriptor, stream);
}

fn producer_descriptor_matches(
    descriptor: p3_async_manifest.Descriptor,
    stream: p3_async_manifest.StreamCanonical,
) bool {
    return descriptor.params.len == 1 and descriptor.params[0].len > "stream<>".len and
        std.mem.startsWith(u8, descriptor.params[0], "stream<") and
        std.mem.endsWith(u8, descriptor.params[0], ">") and
        descriptor.canonical.async_import_module.len != 0 and
        descriptor.canonical.async_import_name.len != 0 and
        std.mem.eql(u8, stream.element, descriptor.params[0][7 .. descriptor.params[0].len - 1]) and
        std.mem.eql(u8, descriptor.member, "consume-via-stream") and
        std.mem.eql(u8, stream.read.import_name, "[async-lower][stream-read-0]consume-via-stream") and
        std.mem.eql(u8, stream.write.import_name, "[async-lower][stream-write-0]consume-via-stream") and
        std.mem.eql(u8, stream.drop_writable.import_name, "[stream-drop-writable-0]consume-via-stream");
}

fn source_from_producer(producer: p3_async_manifest.ProducerCanonical) SourceContract {
    return .{
        .module = producer.source_module,
        .import_name = producer.source_import_name,
        .core_params = producer.source_core_params,
        .core_results = producer.source_core_results,
    };
}

fn sink_from_stream(
    descriptor: p3_async_manifest.Descriptor,
    stream: p3_async_manifest.StreamCanonical,
    capacity: u32,
) SinkContract {
    return .{
        .module = descriptor.canonical.async_import_module,
        .member = descriptor.member,
        .capacity = capacity,
        .read_import = stream.read.import_name,
        .write_import = stream.write.import_name,
        .drop_import = stream.drop_writable.import_name,
    };
}

fn terminal_from_stream(terminal: []const u8, stream: p3_async_manifest.StreamCanonical) TerminalContract {
    return .{
        .close_action = terminal,
        .abort_action = null,
        .cancel_action = stream.cancel_write.import_name,
        .cleanup_order = &.{ .resource, .list, .stream, .future, .subtask, .waitable, .frame },
    };
}

fn ownership_for_direct(layout: p3_async_manifest.RecordLayout) ContractError!OwnershipTransferPlan {
    if (!valid_owned_record_layout(layout, "resource-entry", &.{"ticket"}, &.{0})) return error.UnsupportedProducerContract;
    return .{ .leaves = &direct_ticket_leaves, .parents = &.{} };
}

fn ownership_for_pair(layout: p3_async_manifest.RecordLayout) ContractError!OwnershipTransferPlan {
    if (!valid_owned_record_layout(layout, "resource-pair", &.{ "left", "right" }, &.{ 0, 4 }))
        return error.UnsupportedProducerContract;
    return .{ .leaves = &pair_ticket_leaves, .parents = &.{} };
}

fn ownership_for_triple(layout: p3_async_manifest.RecordLayout) ContractError!OwnershipTransferPlan {
    if (!valid_owned_record_layout(layout, "resource-triple", &.{ "left", "middle", "right" }, &.{ 0, 4, 8 }))
        return error.UnsupportedProducerContract;
    return .{ .leaves = &triple_ticket_leaves, .parents = &.{} };
}

fn ownership_for_nested(layout: p3_async_manifest.RecordLayout) ContractError!OwnershipTransferPlan {
    if (!std.mem.eql(u8, layout.name, "outer") or layout.byte_size != 4 or layout.fields.len != 1 or
        layout.source_fields.len != 1 or !field_matches(layout.fields[0], "ticket", "i32", 0))
        return error.UnsupportedProducerContract;
    const outer = layout.source_fields[0];
    if (!std.mem.eql(u8, outer.name, "inner") or !std.mem.eql(u8, outer.source_type, "inner") or
        outer.storage.len != 0 or outer.ownership != .none or outer.resource != null or
        outer.drop_import != null or outer.nested_fields.len != 1) return error.UnsupportedProducerContract;
    const leaf = outer.nested_fields[0];
    if (!std.mem.eql(u8, leaf.name, "ticket") or !std.mem.eql(u8, leaf.source_type, "ticket") or
        leaf.storage.len != 1 or !std.mem.eql(u8, leaf.storage[0], "ticket") or
        leaf.ownership != .own or leaf.resource == null or !std.mem.eql(u8, leaf.resource.?, "ticket") or
        leaf.drop_import == null or !std.mem.eql(u8, leaf.drop_import.?, "[resource-drop]ticket") or
        leaf.nested_fields.len != 0) return error.UnsupportedProducerContract;
    return .{ .leaves = &nested_ticket_leaves, .parents = &nested_ticket_parents };
}

fn valid_owned_record_layout(
    layout: p3_async_manifest.RecordLayout,
    name: []const u8,
    field_names: []const []const u8,
    offsets: []const u32,
) bool {
    if (!std.mem.eql(u8, layout.name, name) or layout.fields.len != field_names.len or
        layout.source_fields.len != field_names.len or offsets.len != field_names.len or
        layout.byte_size != @as(u32, @intCast(field_names.len * 4))) return false;
    for (field_names, 0..) |field_name, index| {
        if (!field_matches(layout.fields[index], field_name, "i32", offsets[index]) or
            !owned_source_matches(layout.source_fields[index], field_name)) return false;
    }
    return true;
}

fn field_matches(field: p3_async_manifest.RecordField, name: []const u8, core_type: []const u8, offset: u32) bool {
    return std.mem.eql(u8, field.name, name) and std.mem.eql(u8, field.core_type, core_type) and field.offset == offset;
}

fn owned_source_matches(field: p3_async_manifest.RecordSourceField, name: []const u8) bool {
    return std.mem.eql(u8, field.name, name) and std.mem.eql(u8, field.source_type, "ticket") and
        field.storage.len == 1 and std.mem.eql(u8, field.storage[0], name) and field.ownership == .own and
        field.resource != null and std.mem.eql(u8, field.resource.?, "ticket") and
        field.drop_import != null and std.mem.eql(u8, field.drop_import.?, "[resource-drop]ticket") and
        field.nested_fields.len == 0;
}

test "producer contract validates a minimal scalar plan" {
    const value = ProducerContract{
        .descriptor_id = "do:test/producer",
        .source = .{ .module = "source", .import_name = "make", .core_params = &.{}, .core_results = &.{"i32"} },
        .sink = .{ .module = "sink", .member = "consume", .capacity = 1, .read_import = "read", .write_import = "write", .drop_import = "drop" },
        .payload = .{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } },
        .ownership = .{ .leaves = &.{}, .parents = &.{} },
        .terminal = .{ .close_action = "close", .abort_action = null, .cancel_action = "cancel", .cleanup_order = &.{ .stream, .future, .waitable, .frame } },
    };
    try validate_contract(value);
}
