const std = @import("std");
const generated_text = @import("codegen_text.zig");
const lexer = @import("lexer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const producer_contract = @import("codegen_component_producer_contract.zig");
const producer_facts = @import("codegen_component_producer_facts.zig");
const producer_fragments = @import("codegen_component_producer_fragments.zig");
const mapping_probe = @import("codegen_component_producer_mapping_probe.zig");
const pilot_emitter = @import("codegen_component_producer_emitter.zig");
const wit_abi_layout = @import("wit_abi_layout.zig");
const wit_abi_types = @import("wit_abi_types.zig");

const canonical_core_wat = @embedFile("owned_record_stream_producer_template.wat");

const direct_payload_start: u32 = 4086;
const direct_lifecycle_start: u32 = 4491;
const direct_metadata_start: u32 = 6364;
const direct_suffix_start: u32 = 15517;
const direct_descriptor_hash = "6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace";
const direct_fragment_markers = [_][]const u8{
    "[producer-record-byte-size] 4",
    "[producer-record-ticket-offset] 0",
    "[producer-stream-capacity] 1",
    "[producer-ticket-seed] 111",
    "[producer-record-transfer]",
    "[producer-resource-drop-exactly-once]",
    "[producer-child-before-parent-cleanup]",
};
const direct_fragments = [_]producer_fragments.Fragment{
    .{ .name = "direct-prefix", .kind = .prefix, .span = .{ .start = 0, .end = direct_payload_start }, .required_markers = &.{}, .order = 0 },
    .{ .name = "direct-payload", .kind = .payload, .span = .{ .start = direct_payload_start, .end = direct_lifecycle_start }, .required_markers = &direct_fragment_markers, .order = 1 },
    .{ .name = "direct-lifecycle", .kind = .lifecycle, .span = .{ .start = direct_lifecycle_start, .end = direct_metadata_start }, .required_markers = &.{}, .order = 2 },
    .{ .name = "direct-metadata", .kind = .metadata, .span = .{ .start = direct_metadata_start, .end = direct_suffix_start }, .required_markers = &.{}, .order = 3 },
    .{ .name = "direct-suffix", .kind = .suffix, .span = .{ .start = direct_suffix_start, .end = @intCast(canonical_core_wat.len) }, .required_markers = &.{}, .order = 4 },
};

pub const ProducerError = error{UnsupportedP3OwnedRecordStreamProducer};

pub const OwnedRecordStreamProducerPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    source_host_name: []const u8,
    sink_host_name: []const u8,
    ticket_type_name: []const u8,
    record_type_name: []const u8,
    error_type_name: []const u8,
    root_name: []const u8,
    mode_name: []const u8,
    layout: p3_async_manifest.RecordLayout,
    producer: p3_async_manifest.ProducerCanonical,
    contract: producer_contract.ProducerContract,

    pub fn analyze(
        tokens: []const lexer.Token,
        registry: p3_async_manifest.Registry,
    ) ProducerError!OwnedRecordStreamProducerPlan {
        const descriptor = registry.find("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream") orelse
            return error.UnsupportedP3OwnedRecordStreamProducer;
        const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3OwnedRecordStreamProducer) {
            .owned_record_stream_producer => |value| value,
            else => return error.UnsupportedP3OwnedRecordStreamProducer,
        };

        const source = find_host_binding(tokens, .source) orelse return error.UnsupportedP3OwnedRecordStreamProducer;
        const sink = find_host_binding(tokens, .sink) orelse return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_host_bindings(tokens) != 2 or
            !std.mem.eql(u8, source.locator, "do:g6-2-owned-record-producer/source@0.1.0") or
            !std.mem.eql(u8, source.member, "make-ticket") or
            !source_signature_is_exact(tokens, source.signature_open) or
            !std.mem.eql(u8, sink.locator, descriptor.locator) or
            !std.mem.eql(u8, sink.member, descriptor.member) or
            !sink_signature_is_exact(tokens, sink.signature_open)) return error.UnsupportedP3OwnedRecordStreamProducer;

        const ticket = find_resource_decl(tokens) orelse return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_resource_decls(tokens) != 1 or
            !std.mem.eql(u8, ticket.name, "Ticket") or
            !std.mem.eql(u8, ticket.path, "do:g6-2-owned-record-producer/source/ticket") or
            !resource_decl_is_exact(tokens, "Ticket", ticket.path)) return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_record_decls(tokens, "ResourceEntry") != 1 or
            !find_record_decl(tokens, "ResourceEntry", "Ticket") or
            !find_error_decl(tokens, "ProducerError") or
            count_error_decls(tokens, "ProducerError") != 1 or
            !find_producer_function(tokens, "produce", "ProducerError") or
            !find_empty_start(tokens)) return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_top_level_declarations(tokens) != 7 or
            count_top_level_functions(tokens) != 2 or
            count_named_functions(tokens, "produce") != 1 or
            count_named_functions(tokens, "start") != 1 or
            count_token_pair(tokens, "async") != 0 or
            count_intrinsic(tokens, "async") != 0 or
            count_intrinsic(tokens, "await") != 0 or
            count_intrinsic(tokens, "cancel") != 0) return error.UnsupportedP3OwnedRecordStreamProducer;

        if (!std.mem.eql(u8, shape.element, "resource-entry") or
            shape.record_layout.byte_size != 4 or
            shape.record_layout.fields.len != 1 or
            shape.record_layout.source_fields.len != 1 or
            !std.mem.eql(u8, shape.record_layout.name, "resource-entry") or
            !std.mem.eql(u8, shape.record_layout.fields[0].name, "ticket") or
            !std.mem.eql(u8, shape.record_layout.fields[0].core_type, "i32") or
            shape.record_layout.fields[0].offset != 0 or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].name, "ticket") or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].source_type, "ticket") or
            shape.record_layout.source_fields[0].ownership != .own or
            shape.record_layout.source_fields[0].resource == null or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].resource.?, "ticket") or
            shape.record_layout.source_fields[0].drop_import == null or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].drop_import.?, "[resource-drop]ticket") or
            shape.producer.stream_capacity != 1 or
            !std.mem.eql(u8, shape.producer.source_module, "do:g6-2-owned-record-producer/source@0.1.0") or
            !std.mem.eql(u8, shape.producer.source_import_name, "make-ticket") or
            !std.mem.eql(u8, shape.producer.resource_drop_import, "[resource-drop]ticket") or
            !std.mem.eql(u8, shape.producer.terminal, "task-return") or
            shape.producer.runtime_count_param != null or
            shape.producer.runtime_max != null or
            shape.producer.runtime_mode_param == null or
            !std.mem.eql(u8, shape.producer.runtime_mode_param.?, "u32") or
            shape.producer.batch_count != null or
            shape.producer.batch_lengths != null) return error.UnsupportedP3OwnedRecordStreamProducer;

        const contract = producer_contract.producer_contract_from_descriptor(descriptor) catch
            return error.UnsupportedP3OwnedRecordStreamProducer;
        return .{
            .descriptor = descriptor,
            .source_host_name = source.name,
            .sink_host_name = sink.name,
            .ticket_type_name = ticket.name,
            .record_type_name = "ResourceEntry",
            .error_type_name = "ProducerError",
            .root_name = "produce",
            .mode_name = "mode",
            .layout = shape.record_layout,
            .producer = shape.producer,
            .contract = contract,
        };
    }
};

const BindingKind = enum { source, sink };

const HostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    signature_open: usize,
    kind: BindingKind,
};

const ResourceDecl = struct { name: []const u8, path: []const u8 };

pub fn emit_component_wat(allocator: std.mem.Allocator, plan: OwnedRecordStreamProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (plan.layout.byte_size != 4 or plan.layout.fields.len != 1 or
        plan.layout.fields[0].offset != 0 or plan.producer.stream_capacity != 1 or
        !std.mem.eql(u8, plan.layout.fields[0].name, "ticket")) return error.UnsupportedP3OwnedRecordStreamProducer;

    const wat = try generated_text.alloc_block(allocator, 0, canonical_core_wat);
    if (std.mem.indexOf(u8, wat, "__arc_") != null) {
        allocator.free(wat);
        return error.UnsupportedP3OwnedRecordStreamProducer;
    }
    return wat;
}

/// Private-by-convention pilot entry. The default producer route intentionally
/// remains on emit_component_wat until a separate promotion decision.
pub fn emit_component_wat_pilot(allocator: std.mem.Allocator, plan: OwnedRecordStreamProducerPlan) pilot_emitter.PilotError![]u8 {
    validate_direct_plan(plan) catch return error.InvalidAdmission;
    const measured = mapping_probe.fact_for_route("owned-record-direct") orelse return error.InvalidAdmission;
    var frame_facts: producer_facts.RouteFrameFacts = measured.*;
    frame_facts.descriptor_id = plan.contract.descriptor_id;
    return pilot_emitter.emit_pilot_wat(allocator, .{
        .facts = .{
            .route_id = measured.route_id,
            .descriptor_id = plan.contract.descriptor_id,
            .contract = plan.contract,
            .frame_facts = frame_facts,
            .fragments = &direct_fragments,
            .golden_wat = canonical_core_wat,
        },
        .canonical_wit_hash = plan.contract.descriptor_hash orelse "",
    });
}

fn validate_direct_plan(plan: OwnedRecordStreamProducerPlan) pilot_emitter.PilotError!void {
    if (!std.mem.eql(u8, plan.descriptor.locator, "do:g6-2-owned-record-producer@0.1.0") or
        !std.mem.eql(u8, plan.descriptor.member, "consume-via-stream") or
        !std.mem.eql(u8, plan.descriptor.effect, "record-resource-stream-producer") or
        !same_string_list(plan.descriptor.params, &.{"stream<resource-entry>"}) or
        !std.mem.eql(u8, plan.descriptor.result, "Result<nil,error-code>") or
        plan.descriptor.resource != null or plan.descriptor.wit_sha256 == null or
        !std.mem.eql(u8, plan.descriptor.wit_sha256.?, direct_descriptor_hash) or
        !std.mem.eql(u8, plan.descriptor.wit.package, "do:g6-2-owned-record-producer@0.1.0") or
        !std.mem.eql(u8, plan.descriptor.wit.interface, "sink") or
        !std.mem.eql(u8, plan.descriptor.wit.operation, "consume-via-stream") or
        !std.mem.eql(u8, plan.descriptor.wit.world, "owned-record-producer") or
        !std.mem.eql(u8, plan.descriptor.wit.parameter, "data") or
        !same_string_list(plan.descriptor.canonical.core_params, &.{ "i32", "i32" }) or
        !same_string_list(plan.descriptor.canonical.core_results, &.{"i32"}) or
        !same_string_list(plan.descriptor.canonical.completion_params, &.{ "i32", "i32" }) or
        !std.mem.eql(u8, plan.descriptor.canonical.completion, "task-return") or
        !std.mem.eql(u8, plan.descriptor.canonical.async_import_module, "do:g6-2-owned-record-producer/sink@0.1.0") or
        !std.mem.eql(u8, plan.descriptor.canonical.async_import_name, "[async-lower]consume-via-stream") or
        plan.descriptor.canonical.result_payload != null or
        plan.descriptor.canonical.result_area_payload != null or
        plan.descriptor.canonical.future_owned != null or
        plan.descriptor.canonical.error_variants.len != 0 or
        plan.descriptor.canonical.list_resource_layout != null or
        plan.descriptor.canonical.record_list_layout != null or
        plan.descriptor.canonical.parameterized_owned_record_pair_producer != null or
        plan.descriptor.canonical.scalar_list_layout != null or
        plan.descriptor.canonical.scalar_list_producer != null or
        plan.descriptor.canonical.future_input != null or
        plan.descriptor.canonical.future != null or
        plan.descriptor.canonical.variant_stream != null or
        plan.descriptor.canonical.variant_future != null or
        plan.descriptor.canonical.event_layout != null or
        plan.descriptor.canonical.ticket_drop_import != null)
    {
        return error.InvalidAdmission;
    }

    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.InvalidAdmission) {
        .owned_record_stream_producer => |value| value,
        else => return error.InvalidAdmission,
    };
    if (!record_layout_equal(plan.layout, shape.record_layout) or
        !producer_equal(plan.producer, shape.producer) or
        plan.layout.alignment != 4 or shape.record_layout.alignment != 4 or
        !record_layout_equal(plan.descriptor.canonical.record_layout orelse return error.InvalidAdmission, shape.record_layout) or
        !producer_equal(plan.descriptor.canonical.producer orelse return error.InvalidAdmission, shape.producer) or
        !stream_equal(plan.descriptor.canonical.stream orelse return error.InvalidAdmission, shape.stream) or
        !std.mem.eql(u8, plan.source_host_name, "make_ticket") or
        !std.mem.eql(u8, plan.sink_host_name, "consume") or
        !std.mem.eql(u8, plan.ticket_type_name, "Ticket") or
        !std.mem.eql(u8, plan.record_type_name, "ResourceEntry") or
        !std.mem.eql(u8, plan.error_type_name, "ProducerError") or
        !std.mem.eql(u8, plan.root_name, "produce") or
        !std.mem.eql(u8, plan.mode_name, "mode"))
    {
        return error.InvalidAdmission;
    }
    const expected_contract = producer_contract.producer_contract_from_shape(
        plan.descriptor,
        .{ .owned_record_stream_producer = shape },
    ) catch return error.InvalidAdmission;
    if (!contract_equal(plan.contract, expected_contract)) return error.InvalidAdmission;
}

fn record_layout_equal(left: p3_async_manifest.RecordLayout, right: p3_async_manifest.RecordLayout) bool {
    if (!std.mem.eql(u8, left.name, right.name) or left.byte_size != right.byte_size or left.alignment != right.alignment or
        left.fields.len != right.fields.len or left.source_fields.len != right.source_fields.len) return false;
    for (left.fields, right.fields) |a, b| {
        if (!std.mem.eql(u8, a.name, b.name) or !std.mem.eql(u8, a.core_type, b.core_type) or a.offset != b.offset) return false;
    }
    for (left.source_fields, right.source_fields) |a, b| {
        if (!source_field_equal(a, b)) return false;
    }
    return true;
}

fn source_field_equal(left: p3_async_manifest.RecordSourceField, right: p3_async_manifest.RecordSourceField) bool {
    return std.mem.eql(u8, left.name, right.name) and std.mem.eql(u8, left.source_type, right.source_type) and
        same_string_list(left.storage, right.storage) and left.ownership == right.ownership and
        same_optional(left.resource, right.resource) and same_optional(left.drop_import, right.drop_import) and
        left.nested_fields.len == right.nested_fields.len;
}

fn producer_equal(left: p3_async_manifest.ProducerCanonical, right: p3_async_manifest.ProducerCanonical) bool {
    return std.mem.eql(u8, left.source_module, right.source_module) and
        std.mem.eql(u8, left.source_import_name, right.source_import_name) and
        same_string_list(left.source_core_params, right.source_core_params) and
        same_string_list(left.source_core_results, right.source_core_results) and
        std.mem.eql(u8, left.resource_drop_import, right.resource_drop_import) and
        left.stream_capacity == right.stream_capacity and std.mem.eql(u8, left.terminal, right.terminal) and
        same_optional(left.runtime_count_param, right.runtime_count_param) and left.runtime_max == right.runtime_max and
        same_optional(left.runtime_mode_param, right.runtime_mode_param) and left.batch_count == right.batch_count and
        same_optional_u32_slice(left.batch_lengths, right.batch_lengths);
}

fn stream_equal(left: p3_async_manifest.StreamCanonical, right: p3_async_manifest.StreamCanonical) bool {
    return std.mem.eql(u8, left.element, right.element) and operation_equal(left.new, right.new) and
        operation_equal(left.cancel_read, right.cancel_read) and operation_equal(left.cancel_write, right.cancel_write) and
        operation_equal(left.drop_readable, right.drop_readable) and operation_equal(left.drop_writable, right.drop_writable) and
        operation_equal(left.read, right.read) and operation_equal(left.write, right.write);
}

fn operation_equal(left: p3_async_manifest.StreamOperation, right: p3_async_manifest.StreamOperation) bool {
    return std.mem.eql(u8, left.import_name, right.import_name) and
        same_string_list(left.core_params, right.core_params) and same_string_list(left.core_results, right.core_results);
}

fn contract_equal(left: producer_contract.ProducerContract, right: producer_contract.ProducerContract) bool {
    if (!std.mem.eql(u8, left.descriptor_id, right.descriptor_id) or !same_optional(left.descriptor_hash, right.descriptor_hash) or
        !std.mem.eql(u8, left.source.module, right.source.module) or !std.mem.eql(u8, left.source.import_name, right.source.import_name) or
        !same_string_list(left.source.core_params, right.source.core_params) or !same_string_list(left.source.core_results, right.source.core_results) or
        !std.mem.eql(u8, left.sink.module, right.sink.module) or !std.mem.eql(u8, left.sink.member, right.sink.member) or
        left.sink.capacity != right.sink.capacity or !std.mem.eql(u8, left.sink.read_import, right.sink.read_import) or
        !std.mem.eql(u8, left.sink.write_import, right.sink.write_import) or !std.mem.eql(u8, left.sink.drop_import, right.sink.drop_import) or
        !payload_equal(left.payload, right.payload) or !ownership_equal(left.ownership, right.ownership) or
        !terminal_equal(left.terminal, right.terminal) or !same_optional(left.runtime_count_param, right.runtime_count_param) or
        left.runtime_max != right.runtime_max or !same_optional(left.runtime_mode_param, right.runtime_mode_param) or
        left.batch_count != right.batch_count or !same_u32_slice(left.batch_lengths, right.batch_lengths) or
        left.list_allocations.len != right.list_allocations.len or !same_string_list(left.producer_core_params, right.producer_core_params) or
        !same_string_list(left.producer_core_results, right.producer_core_results) or !same_optional(left.left_seed_param, right.left_seed_param) or
        !same_optional(left.right_seed_param, right.right_seed_param)) return false;
    for (left.list_allocations, right.list_allocations) |a, b| {
        if (!same_string_list(a.path, b.path) or !std.mem.eql(u8, a.element_core_type, b.element_core_type) or
            a.pointer_offset != b.pointer_offset or a.length_offset != b.length_offset or a.element_stride != b.element_stride or
            a.max_items != b.max_items or !std.mem.eql(u8, a.release_import, b.release_import)) return false;
    }
    return true;
}

fn payload_equal(left: producer_contract.PayloadLayout, right: producer_contract.PayloadLayout) bool {
    return switch (left) {
        .record => |a| switch (right) {
            .record => |b| record_layout_equal(a, b),
            else => false,
        },
        .scalar => |a| switch (right) {
            .scalar => |b| std.mem.eql(u8, a.core_type, b.core_type) and a.byte_size == b.byte_size and a.alignment == b.alignment,
            else => false,
        },
        .list => |a| switch (right) {
            .list => |b| a.pointer_offset == b.pointer_offset and a.length_offset == b.length_offset and a.element_stride == b.element_stride and a.max_items == b.max_items,
            else => false,
        },
    };
}

fn ownership_equal(left: producer_contract.OwnershipTransferPlan, right: producer_contract.OwnershipTransferPlan) bool {
    if (left.complete_write_required != right.complete_write_required or left.pre_transfer_reverse_order != right.pre_transfer_reverse_order or
        left.leaves.len != right.leaves.len or left.parents.len != right.parents.len) return false;
    for (left.leaves, right.leaves) |a, b| {
        if (!same_string_list(a.path, b.path) or !std.mem.eql(u8, a.resource, b.resource) or a.handle_offset != b.handle_offset or
            !std.mem.eql(u8, a.drop_import, b.drop_import) or a.bit != b.bit or a.absence_sentinel != b.absence_sentinel) return false;
    }
    for (left.parents, right.parents) |a, b| if (!same_string_list(a.path, b.path) or a.bit != b.bit) return false;
    return true;
}

fn terminal_equal(left: producer_contract.TerminalContract, right: producer_contract.TerminalContract) bool {
    if (!std.mem.eql(u8, left.close_action, right.close_action) or !same_optional(left.abort_action, right.abort_action) or
        !std.mem.eql(u8, left.cancel_action, right.cancel_action) or left.cleanup_order.len != right.cleanup_order.len) return false;
    for (left.cleanup_order, right.cleanup_order) |a, b| if (a != b) return false;
    return true;
}

fn same_string_list(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.mem.eql(u8, a, b)) return false;
    return true;
}

fn same_optional(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn same_u32_slice(left: []const u32, right: []const u32) bool {
    return std.mem.eql(u32, left, right);
}

fn same_optional_u32_slice(left: ?[]const u32, right: ?[]const u32) bool {
    if (left == null or right == null) return left == null and right == null;
    return same_u32_slice(left.?, right.?);
}

pub fn emit_component_wat_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wat(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, plan: OwnedRecordStreamProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (!std.mem.eql(u8, plan.descriptor.wit.world, "owned-record-producer")) {
        return error.UnsupportedP3OwnedRecordStreamProducer;
    }
    return generated_text.alloc_block(allocator, 0,
        \\package do:g6-2-owned-record-producer@0.1.0;
        \\
        \\interface types {
        \\  enum error-code { io, pipe, invalid-mode }
        \\  resource ticket {}
        \\  record resource-entry { ticket: own<ticket> }
        \\}
        \\
        \\interface source {
        \\  use types.{ticket};
        \\  make-ticket: func(seed: u32) -> own<ticket>;
        \\}
        \\
        \\interface sink {
        \\  use types.{error-code, resource-entry};
        \\  consume-via-stream: async func(
        \\    data: stream<resource-entry>
        \\  ) -> result<_, error-code>;
        \\}
        \\
        \\world owned-record-producer {
        \\  use types.{error-code};
        \\  import source;
        \\  import sink;
        \\  export produce: async func(mode: u32) -> result<_, error-code>;
        \\}
        \\
    );
}

pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wit(allocator, plan);
}

fn validate_internal_plans(allocator: std.mem.Allocator, plan: OwnedRecordStreamProducerPlan) ProducerError!void {
    producer_contract.validate_contract(plan.contract) catch return error.UnsupportedP3OwnedRecordStreamProducer;
    if (!std.mem.eql(u8, plan.contract.descriptor_id, plan.descriptor.locator) or
        plan.contract.sink.capacity != plan.producer.stream_capacity) return error.UnsupportedP3OwnedRecordStreamProducer;
    const record = switch (plan.contract.payload) {
        .record => |value| value,
        else => return error.UnsupportedP3OwnedRecordStreamProducer,
    };
    if (record.byte_size != plan.layout.byte_size or record.fields.len != plan.layout.fields.len) {
        return error.UnsupportedP3OwnedRecordStreamProducer;
    }
    var ticket = wit_abi_types.AbiType.resource(allocator, "ticket", .own) catch return error.UnsupportedP3OwnedRecordStreamProducer;
    defer ticket.deinit();
    var entry = wit_abi_types.AbiType.record(allocator, &.{
        .{ .name = "ticket", .value = &ticket },
    }) catch return error.UnsupportedP3OwnedRecordStreamProducer;
    defer entry.deinit();

    var layout = wit_abi_layout.LayoutPlan.record(allocator, &entry, .{
        .byte_size = plan.layout.byte_size,
        .alignment = 4,
        .fields = &.{.{
            .name = "ticket",
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .indirect = null,
        }},
    }) catch return error.UnsupportedP3OwnedRecordStreamProducer;
    defer layout.deinit();
    if (layout.byte_size != 4 or layout.alignment != 4 or layout.record_fields.len != 1 or
        layout.record_fields[0].offset != 0 or !std.mem.eql(u8, layout.record_fields[0].name, "ticket"))
    {
        return error.UnsupportedP3OwnedRecordStreamProducer;
    }
}

fn find_host_binding(tokens: []const lexer.Token, wanted: BindingKind) ?HostBinding {
    var found: ?HostBinding = null;
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or
            tokens[idx + 7].kind != .string or !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(")) continue;
        const kind: BindingKind = if (tok_eq(tokens[idx + 3], "host_func")) .source else if (tok_eq(tokens[idx + 3], "host_async_func")) .sink else continue;
        if (kind != wanted) continue;
        const close = find_matching(tokens, idx + 9, "(", ")") orelse continue;
        if (close + 3 >= tokens.len or !tok_eq(tokens[close + 1], "-") or !tok_eq(tokens[close + 2], ">") or found != null) return null;
        found = .{
            .name = tokens[idx].lexeme,
            .locator = string_body(tokens[idx + 5].lexeme) orelse return null,
            .member = string_body(tokens[idx + 7].lexeme) orelse return null,
            .signature_open = idx + 9,
            .kind = kind,
        };
    }
    return found;
}

fn count_host_bindings(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "=") and tok_eq(tokens[idx + 2], "@") and
            (tok_eq(tokens[idx + 3], "host_func") or tok_eq(tokens[idx + 3], "host_async_func"))) count += 1;
    }
    return count;
}

fn count_resource_decls(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 5 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "=") and tok_eq(tokens[idx + 2], "@") and
            tok_eq(tokens[idx + 3], "wasi_resource") and tok_eq(tokens[idx + 4], "(") and tokens[idx + 5].kind == .string) count += 1;
    }
    return count;
}

fn count_record_decls(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "{")) count += 1;
    }
    return count;
}

fn count_error_decls(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 2 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "error") and tok_eq(tokens[idx + 2], "=")) count += 1;
    }
    return count;
}

fn count_top_level_declarations(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var paren_depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "(")) {
            paren_depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], ")")) {
            if (paren_depth > 0) paren_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or paren_depth != 0 or tokens[idx].kind != .ident) continue;
        const previous_is_at = idx > 0 and tok_eq(tokens[idx - 1], "@");
        const previous_is_ident = idx > 0 and tokens[idx - 1].kind == .ident;
        const is_declaration_head =
            (tok_eq(tokens[idx + 1], "=") and !previous_is_at and
                !(tok_eq(tokens[idx], "error") and previous_is_ident)) or
            (tok_eq(tokens[idx + 1], "{") and !previous_is_at) or
            (tok_eq(tokens[idx + 1], "(") and !previous_is_at) or
            tok_eq(tokens[idx + 1], "error");
        if (is_declaration_head) {
            count += 1;
        }
    }
    return count;
}

fn source_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 2 and tok_eq(tokens[open + 1], "u32") and close + 3 < tokens.len and
        tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and tok_eq(tokens[close + 3], "Ticket");
}

fn sink_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 5 and tok_eq(tokens[open + 1], "StreamWriter") and tok_eq(tokens[open + 2], "<") and
        tok_eq(tokens[open + 3], "ResourceEntry") and tok_eq(tokens[open + 4], ">") and
        tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and
        tok_eq(tokens[close + 3], "Result") and tok_eq(tokens[close + 4], "<") and tok_eq(tokens[close + 5], "nil") and
        tok_eq(tokens[close + 6], ",") and tok_eq(tokens[close + 7], "ProducerError") and tok_eq(tokens[close + 8], ">");
}

fn find_resource_decl(tokens: []const lexer.Token) ?ResourceDecl {
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "wasi_resource") or !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string) continue;
        return .{ .name = tokens[idx].lexeme, .path = string_body(tokens[idx + 5].lexeme) orelse continue };
    }
    return null;
}

fn resource_decl_is_exact(tokens: []const lexer.Token, name: []const u8, path: []const u8) bool {
    var idx: usize = 0;
    while (idx + 12 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "wasi_resource") or !tok_eq(tokens[idx + 4], "(") or
            tokens[idx + 5].kind != .string or !std.mem.eql(u8, string_body(tokens[idx + 5].lexeme) orelse return false, path) or
            !tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 7], "{") or !tok_eq(tokens[idx + 8], ".id") or
            !tok_eq(tokens[idx + 9], "i64") or !tok_eq(tokens[idx + 10], "}") or !tok_eq(tokens[idx + 11], ")")) continue;
        return true;
    }
    return false;
}

fn find_record_decl(tokens: []const lexer.Token, name: []const u8, field_type: []const u8) bool {
    var idx: usize = 0;
    while (idx + 5 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "{") or !tok_eq(tokens[idx + 2], ".ticket") or
            !tok_eq(tokens[idx + 3], field_type) or !tok_eq(tokens[idx + 4], "}")) continue;
        return true;
    }
    return false;
}

fn find_error_decl(tokens: []const lexer.Token, name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "error") and tok_eq(tokens[idx + 2], "=") and
            tok_eq(tokens[idx + 3], "Io") and tok_eq(tokens[idx + 4], "|") and tok_eq(tokens[idx + 5], "Pipe") and
            tok_eq(tokens[idx + 6], "|") and tok_eq(tokens[idx + 7], "InvalidMode")) return true;
    }
    return false;
}

fn find_producer_function(tokens: []const lexer.Token, name: []const u8, error_name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "(")) continue;
        const params_close = find_matching(tokens, idx + 1, "(", ")") orelse continue;
        if (params_close != idx + 4 or !tok_eq(tokens[idx + 2], "mode") or !tok_eq(tokens[idx + 3], "u32") or
            !tok_eq(tokens[params_close + 1], "-") or !tok_eq(tokens[params_close + 2], ">") or
            !tok_eq(tokens[params_close + 3], "Result") or !tok_eq(tokens[params_close + 4], "<") or
            !tok_eq(tokens[params_close + 5], "nil") or !tok_eq(tokens[params_close + 6], ",") or
            !tok_eq(tokens[params_close + 7], error_name) or !tok_eq(tokens[params_close + 8], ">") or
            !tok_eq(tokens[params_close + 9], "{")) continue;
        const body_close = find_matching(tokens, params_close + 9, "{", "}") orelse continue;
        return body_close == params_close + 14 and tok_eq(tokens[params_close + 10], "return") and
            tok_eq(tokens[params_close + 11], "Ok") and tok_eq(tokens[params_close + 12], "(") and
            tok_eq(tokens[params_close + 13], ")");
    }
    return false;
}

fn find_empty_start(tokens: []const lexer.Token) bool {
    var idx: usize = 0;
    while (idx + 4 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "start") and tok_eq(tokens[idx + 1], "(") and tok_eq(tokens[idx + 2], ")") and
            tok_eq(tokens[idx + 3], "{") and tok_eq(tokens[idx + 4], "}")) return true;
    }
    return false;
}

fn count_top_level_functions(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "(") and
            (idx == 0 or !tok_eq(tokens[idx - 1], "@"))) count += 1;
    }
    return count;
}

fn count_named_functions(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "(")) count += 1;
    }
    return count;
}

fn count_token_pair(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    for (tokens) |token| {
        if (tok_eq(token, name)) count += 1;
    }
    return count;
}

fn count_intrinsic(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "@") and tok_eq(tokens[idx + 1], name)) count += 1;
    }
    return count;
}

fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) ?usize {
    if (open_idx >= tokens.len or !tok_eq(tokens[open_idx], open)) return null;
    var depth: usize = 0;
    for (tokens[open_idx..], 0..) |token, offset| {
        if (tok_eq(token, open)) depth += 1;
        if (tok_eq(token, close)) {
            depth -= 1;
            if (depth == 0) return open_idx + offset;
        }
    }
    return null;
}

fn string_body(lexeme: []const u8) ?[]const u8 {
    if (lexeme.len < 2 or lexeme[0] != '"' or lexeme[lexeme.len - 1] != '"') return null;
    return lexeme[1 .. lexeme.len - 1];
}

fn tok_eq(token: lexer.Token, expected: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, expected);
}

const exact_source =
    \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
    \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
    \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
    \\ResourceEntry { .ticket Ticket }
    \\ProducerError error = Io | Pipe | InvalidMode
    \\produce(mode u32) -> Result<nil, ProducerError> {
    \\    return Ok()
    \\}
    \\start() {}
;

fn expect_plan_error(source: []const u8) !void {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(
        error.UnsupportedP3OwnedRecordStreamProducer,
        OwnedRecordStreamProducerPlan.analyze(tokens, registry),
    );
}

test "owned record producer plan accepts the exact Do source" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
    defer std.testing.allocator.free(tokens);

    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("make_ticket", plan.source_host_name);
    try std.testing.expectEqualStrings("consume", plan.sink_host_name);
    try std.testing.expectEqualStrings("Ticket", plan.ticket_type_name);
    try std.testing.expectEqualStrings("ResourceEntry", plan.record_type_name);
    try std.testing.expectEqualStrings("ProducerError", plan.error_type_name);
    try std.testing.expectEqualStrings("produce", plan.root_name);
    try std.testing.expectEqualStrings("mode", plan.mode_name);
    try std.testing.expectEqual(@as(u32, 4), plan.layout.byte_size);
    try std.testing.expectEqual(@as(u32, 1), plan.producer.stream_capacity);
    try std.testing.expectEqualStrings(plan.descriptor.locator, plan.contract.descriptor_id);
    try std.testing.expectEqual(@as(usize, 1), plan.contract.ownership.leaves.len);
    try std.testing.expectEqual(@as(u32, 0), plan.contract.ownership.leaves[0].handle_offset);
}

test "owned record producer emitter preserves the pinned direct-record contracts" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
    defer std.testing.allocator.free(tokens);

    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    const wat = try emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-byte-size] 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-transfer]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-resource-drop-exactly-once]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);

    const wit = try emit_component_wit(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:g6-2-owned-record-producer@0.1.0;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "data: stream<resource-entry>\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world owned-record-producer") != null);
}

test "owned record producer plan rejects list-shaped sink" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects an unrelated record element" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<OtherEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\OtherEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a borrowed record field" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket borrow<Ticket> }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a second host binding" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\extra = @host_func("env", "extra", () -> nil)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a changed resource path" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/other-ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects an async ticket source" {
    try expect_plan_error(
        \\make_ticket = @host_async_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a non-sentinel producer body" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Err(Io) }
        \\start() {}
    );
}

test "owned record producer plan rejects an await intrinsic" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() { @await(mode) }
    );
}
