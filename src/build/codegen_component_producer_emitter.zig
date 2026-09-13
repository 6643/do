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
    OutOfMemory,
};

pub const PilotFacts = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    contract: producer_contract.ProducerContract,
    frame_facts: facts.RouteFrameFacts,
    fragments: []const fragments.Fragment,
    golden_wat: []const u8,
};

pub const PilotInput = struct {
    facts: PilotFacts,
    canonical_wit_hash: []const u8,
    template_wat: []const u8,
};

const direct_route_id = "owned-record-direct";
const direct_descriptor_id = "do:g6-2-owned-record-producer@0.1.0";
const direct_source_module = "do:g6-2-owned-record-producer/source@0.1.0";
const direct_sink_module = "do:g6-2-owned-record-producer/sink@0.1.0";

pub fn emit_pilot_wat(allocator: std.mem.Allocator, input: PilotInput) PilotError![]u8 {
    try validate_identity_and_hash(input);
    try validate_direct_admission(input.facts.contract);
    if (!facts.route_facts_equal(input.facts.frame_facts, facts.direct_route_facts())) return error.InvalidAdmission;

    const map = state_ir.build_frame_map(.{
        .route_id = input.facts.route_id,
        .descriptor_id = input.facts.descriptor_id,
        .contract = input.facts.contract,
        .frame_facts = input.facts.frame_facts,
    }) catch return error.InvalidMap;
    const lifecycle = state_ir.build_lifecycle_ir(input.facts.contract, map) catch return error.InvalidLifecycle;

    validate_fragment_marker_ownership(input.facts.fragments, map) catch return error.InvalidFragments;
    const assembled = fragments.assemble_with_lifecycle(allocator, input.template_wat, input.facts.fragments, lifecycle) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.LifecycleMismatch => return error.InvalidLifecycle,
        else => return error.InvalidFragments,
    };
    errdefer allocator.free(assembled);

    if (std.mem.indexOf(u8, assembled, "__arc_") != null) return error.ArcRuntimeMarker;
    if (contains_canonical_gc_reference(assembled)) {
        return error.CanonicalGcReference;
    }
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
    if (input.canonical_wit_hash.len == 0 or !std.mem.eql(u8, input.canonical_wit_hash, facts.direct_descriptor_hash)) return error.InvalidHash;
    const contract_hash = input.facts.contract.descriptor_hash orelse return error.InvalidHash;
    if (!std.mem.eql(u8, contract_hash, facts.direct_descriptor_hash) or
        !std.mem.eql(u8, input.canonical_wit_hash, contract_hash)) return error.InvalidHash;
}

fn validate_fragment_marker_ownership(fragment_table: []const fragments.Fragment, map: state_ir.CanonicalFrameMap) PilotError!void {
    for (fragment_table) |fragment| {
        for (fragment.required_markers) |required| {
            if (fragment.kind != .payload or count_marker_owners(fragment_table, required) != 1 or
                !marker_matches_fact(required, map.markers)) return error.InvalidFragments;
        }
    }
    for (map.markers) |marker| {
        var owner_count: usize = 0;
        for (fragment_table) |fragment| {
            for (fragment.required_markers) |required| {
                if (marker_matches_name(required, marker.name)) owner_count += 1;
            }
        }
        if (owner_count != 1) return error.InvalidFragments;
    }
}

fn count_marker_owners(fragment_table: []const fragments.Fragment, required: []const u8) usize {
    var count: usize = 0;
    for (fragment_table) |fragment| {
        for (fragment.required_markers) |candidate| {
            if (std.mem.eql(u8, candidate, required)) count += 1;
        }
    }
    return count;
}

fn marker_matches_fact(required: []const u8, markers: []const facts.MarkerBinding) bool {
    for (markers) |marker| if (marker_matches_name(required, marker.name)) {
        if (marker.expected_value) |expected| {
            const prefix_len = marker.name.len + 2;
            return required.len == prefix_len + 1 + expected.len and required[prefix_len] == ' ' and
                marker_matches_name(required, marker.name) and
                std.mem.eql(u8, required[prefix_len + 1 ..], expected);
        }
        return required.len == marker.name.len + 2;
    };
    return false;
}

fn marker_matches_name(required: []const u8, name: []const u8) bool {
    return required.len >= name.len + 2 and required[0] == '[' and
        required[name.len + 1] == ']' and std.mem.eql(u8, required[1 .. name.len + 1], name);
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
    var index: usize = 0;
    var block_comment_depth: usize = 0;
    var line_comment = false;
    var string = false;
    var escaped = false;
    var open_paren = false;
    while (index < wat.len) {
        if (line_comment) {
            if (wat[index] == '\n') line_comment = false;
            index += 1;
            continue;
        }
        if (block_comment_depth != 0) {
            if (index + 1 < wat.len and wat[index] == '(' and wat[index + 1] == ';') {
                block_comment_depth += 1;
                index += 2;
            } else if (index + 1 < wat.len and wat[index] == ';' and wat[index + 1] == ')') {
                block_comment_depth -= 1;
                index += 2;
            } else {
                index += 1;
            }
            continue;
        }
        if (string) {
            if (escaped) {
                escaped = false;
            } else if (wat[index] == '\\') {
                escaped = true;
            } else if (wat[index] == '"') {
                string = false;
            }
            index += 1;
            continue;
        }
        if (index + 1 < wat.len and wat[index] == ';' and wat[index + 1] == ';') {
            line_comment = true;
            index += 2;
            continue;
        }
        if (index + 1 < wat.len and wat[index] == '(' and wat[index + 1] == ';') {
            block_comment_depth = 1;
            index += 2;
            continue;
        }
        if (wat[index] == ';') {
            index += 1;
            continue;
        }
        if (wat[index] == '"') {
            string = true;
            index += 1;
            continue;
        }
        if (wat[index] == '(') {
            open_paren = true;
            index += 1;
            continue;
        }
        if (wat[index] == ')') {
            open_paren = false;
            index += 1;
            continue;
        }
        if (std.ascii.isWhitespace(wat[index])) {
            index += 1;
            continue;
        }
        const start = index;
        while (index < wat.len and !std.ascii.isWhitespace(wat[index]) and wat[index] != '(' and wat[index] != ')' and wat[index] != '"' and wat[index] != ';') {
            index += 1;
        }
        const token = wat[start..index];
        if ((open_paren and std.mem.eql(u8, token, "ref")) or is_gc_token(token)) return true;
        open_paren = false;
    }
    return false;
}

fn is_gc_token(token: []const u8) bool {
    const gc_tokens = [_][]const u8{
        "externref",      "anyref",          "eqref",           "funcref",            "i31ref",             "structref",          "arrayref",
        "i31.new",        "i31.get_s",       "i31.get_u",       "ref.i31",            "ref.null",           "ref.is_null",        "ref.func",
        "ref.eq",         "ref.as_non_null", "ref.cast",        "ref.test",           "struct.new",         "struct.new_default", "struct.get",
        "struct.get_s",   "struct.get_u",    "struct.set",      "array.new",          "array.new_default",  "array.new_fixed",    "array.get",
        "array.get_s",    "array.get_u",     "array.set",       "array.len",          "array.copy",         "array.fill",         "array.new_data",
        "array.new_elem", "array.init_data", "array.init_elem", "any.convert_extern", "extern.convert_any", "call_ref",           "return_call_ref",
        "br_on_cast",     "br_on_cast_fail", "br_on_non_null",  "br_on_null",
    };
    for (gc_tokens) |gc_token| if (std.mem.eql(u8, token, gc_token)) return true;
    return false;
}
