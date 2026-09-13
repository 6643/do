const std = @import("std");
const facts = @import("codegen_component_producer_facts.zig");
const fragments = @import("codegen_component_producer_fragments.zig");
const producer_contract = @import("codegen_component_producer_contract.zig");
const state_ir = @import("codegen_component_producer_state_ir.zig");

pub const PilotError = error{
    InvalidAdmission,
    InvalidIdentity,
    InvalidHash,
    InvalidMap,
    InvalidLifecycle,
    InvalidFragments,
    ByteParityMismatch,
    ArcRuntimeMarker,
    CanonicalGcReference,
};

pub const PilotFacts = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    contract: producer_contract.ProducerContract,
    frame_facts: facts.RouteFrameFacts,
    fragments: []const fragments.Fragment,
    golden_wat: []const u8,
    /// The immutable fragment source. A blank value preserves the compact
    /// standalone API by treating golden_wat as the source for callers that
    /// do not need an independent parity oracle.
    template_wat: []const u8 = "",
};

pub const PilotInput = struct {
    facts: PilotFacts,
    canonical_wit_hash: []const u8,
};

const direct_route_id = "owned-record-direct";
const direct_descriptor_id = "do:g6-2-owned-record-producer@0.1.0";
const direct_source_module = "do:g6-2-owned-record-producer/source@0.1.0";
const direct_sink_module = "do:g6-2-owned-record-producer/sink@0.1.0";

pub fn emit_pilot_wat(allocator: std.mem.Allocator, input: PilotInput) PilotError![]u8 {
    try validate_identity_and_hash(input);
    try validate_direct_admission(input.facts.contract);

    const map = state_ir.build_frame_map(.{
        .route_id = input.facts.route_id,
        .descriptor_id = input.facts.descriptor_id,
        .contract = input.facts.contract,
        .frame_facts = input.facts.frame_facts,
    }) catch return error.InvalidMap;
    const lifecycle = state_ir.build_lifecycle_ir(input.facts.contract, map) catch return error.InvalidLifecycle;

    const template_wat = if (input.facts.template_wat.len == 0) input.facts.golden_wat else input.facts.template_wat;
    fragments.validate_fragment_table(template_wat, input.facts.fragments) catch return error.InvalidFragments;
    const assembled = fragments.assemble(allocator, template_wat, input.facts.fragments) catch return error.InvalidFragments;
    errdefer allocator.free(assembled);

    _ = lifecycle;
    if (std.mem.indexOf(u8, assembled, "__arc_") != null) return error.ArcRuntimeMarker;
    if (contains_canonical_gc_reference(assembled)) return error.CanonicalGcReference;
    if (!std.mem.eql(u8, assembled, input.facts.golden_wat)) return error.ByteParityMismatch;

    return assembled;
}

fn validate_identity_and_hash(input: PilotInput) PilotError!void {
    if (!std.mem.eql(u8, input.facts.route_id, direct_route_id) or
        !std.mem.eql(u8, input.facts.descriptor_id, direct_descriptor_id) or
        !std.mem.eql(u8, input.facts.contract.descriptor_id, direct_descriptor_id) or
        !std.mem.eql(u8, input.facts.frame_facts.route_id, direct_route_id) or
        !std.mem.eql(u8, input.facts.frame_facts.descriptor_id, direct_descriptor_id))
    {
        return error.InvalidIdentity;
    }
    if (input.canonical_wit_hash.len == 0) return error.InvalidHash;
    const contract_hash = input.facts.contract.descriptor_hash orelse return error.InvalidHash;
    if (!std.mem.eql(u8, input.canonical_wit_hash, contract_hash)) return error.InvalidHash;
}

fn validate_direct_admission(contract: producer_contract.ProducerContract) PilotError!void {
    if (!std.mem.eql(u8, contract.source.module, direct_source_module) or
        !std.mem.eql(u8, contract.source.import_name, "make-ticket") or
        !same_string_list(contract.source.core_params, &.{"i32"}) or
        !same_string_list(contract.source.core_results, &.{"i32"}) or
        !std.mem.eql(u8, contract.sink.module, direct_sink_module) or
        !std.mem.eql(u8, contract.sink.member, "consume-via-stream") or
        contract.sink.capacity != 1 or
        !std.mem.eql(u8, contract.sink.read_import, "[async-lower][stream-read-0]consume-via-stream") or
        !std.mem.eql(u8, contract.sink.write_import, "[async-lower][stream-write-0]consume-via-stream") or
        !std.mem.eql(u8, contract.sink.drop_import, "[stream-drop-writable-0]consume-via-stream"))
    {
        return error.InvalidAdmission;
    }

    const record = switch (contract.payload) {
        .record => |value| value,
        else => return error.InvalidAdmission,
    };
    if (!std.mem.eql(u8, record.name, "resource-entry") or record.byte_size != 4 or record.fields.len != 1 or
        !std.mem.eql(u8, record.fields[0].name, "ticket") or
        !std.mem.eql(u8, record.fields[0].core_type, "i32") or record.fields[0].offset != 0 or
        record.source_fields.len != 1 or !std.mem.eql(u8, record.source_fields[0].name, "ticket") or
        !std.mem.eql(u8, record.source_fields[0].source_type, "ticket") or
        record.source_fields[0].ownership != .own or record.source_fields[0].resource == null or
        !std.mem.eql(u8, record.source_fields[0].resource.?, "ticket") or
        record.source_fields[0].drop_import == null or
        !std.mem.eql(u8, record.source_fields[0].drop_import.?, "[resource-drop]ticket"))
    {
        return error.InvalidAdmission;
    }
    if (contract.ownership.leaves.len != 1 or contract.ownership.parents.len != 0 or
        contract.ownership.leaves[0].path.len != 1 or
        !std.mem.eql(u8, contract.ownership.leaves[0].path[0], "ticket") or
        !std.mem.eql(u8, contract.ownership.leaves[0].resource, "ticket") or
        contract.ownership.leaves[0].handle_offset != 0 or
        !std.mem.eql(u8, contract.ownership.leaves[0].drop_import, "[resource-drop]ticket") or
        contract.ownership.leaves[0].bit != 0 or contract.list_allocations.len != 0 or
        contract.runtime_count_param != null or contract.runtime_max != null or
        contract.runtime_mode_param == null or !std.mem.eql(u8, contract.runtime_mode_param.?, "u32") or
        contract.batch_count != null or contract.batch_lengths.len != 0)
    {
        return error.InvalidAdmission;
    }
}

fn same_string_list(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_item, right_item| {
        if (!std.mem.eql(u8, left_item, right_item)) return false;
    }
    return true;
}

fn contains_canonical_gc_reference(wat: []const u8) bool {
    const gc_tokens = [_][]const u8{
        "(ref",
        "externref",
        "anyref",
        "eqref",
        "funcref",
        "structref",
        "arrayref",
    };
    for (gc_tokens) |token| if (std.mem.indexOf(u8, wat, token) != null) return true;
    return false;
}
