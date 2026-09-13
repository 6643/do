const std = @import("std");
const emitter = @import("codegen_component_producer_emitter.zig");
const facts = @import("codegen_component_producer_facts.zig");
const fragments = @import("codegen_component_producer_fragments.zig");
const lexer = @import("lexer.zig");
const mapping_probe = @import("codegen_component_producer_mapping_probe.zig");
const producer = @import("codegen_component_owned_record_stream_producer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

const direct_template: []const u8 = @embedFile("owned_record_stream_producer_template.wat");

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

const payload_start: u32 = 4086;
const lifecycle_start: u32 = 4491;
const metadata_start: u32 = 6364;
const suffix_start: u32 = 15517;
const direct_markers = [_][]const u8{
    "[producer-record-byte-size] 4",
    "[producer-record-ticket-offset] 0",
    "[producer-stream-capacity] 1",
    "[producer-ticket-seed] 111",
    "[producer-record-transfer]",
    "[producer-resource-drop-exactly-once]",
    "[producer-child-before-parent-cleanup]",
};
const direct_fragments = [_]fragments.Fragment{
    .{ .name = "direct-prefix", .kind = .prefix, .span = .{ .start = 0, .end = payload_start }, .required_markers = &.{}, .order = 0 },
    .{ .name = "direct-payload", .kind = .payload, .span = .{ .start = payload_start, .end = lifecycle_start }, .required_markers = &direct_markers, .order = 1 },
    .{ .name = "direct-lifecycle", .kind = .lifecycle, .span = .{ .start = lifecycle_start, .end = metadata_start }, .required_markers = &.{}, .order = 2 },
    .{ .name = "direct-metadata", .kind = .metadata, .span = .{ .start = metadata_start, .end = suffix_start }, .required_markers = &.{}, .order = 3 },
    .{ .name = "direct-suffix", .kind = .suffix, .span = .{ .start = suffix_start, .end = direct_template.len }, .required_markers = &.{}, .order = 4 },
};

const PlanContext = struct {
    registry: p3_async_manifest.Registry,
    tokens: []lexer.Token,
    plan: producer.OwnedRecordStreamProducerPlan,

    fn init() !PlanContext {
        var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
        errdefer registry.deinit(std.testing.allocator);
        const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
        errdefer std.testing.allocator.free(tokens);
        const plan = try producer.OwnedRecordStreamProducerPlan.analyze(tokens, registry);
        return .{ .registry = registry, .tokens = tokens, .plan = plan };
    }

    fn deinit(self: *PlanContext) void {
        std.testing.allocator.free(self.tokens);
        self.registry.deinit(std.testing.allocator);
    }
};

fn pilot_input(plan: producer.OwnedRecordStreamProducerPlan) emitter.PilotInput {
    const measured = mapping_probe.fact_for_route("owned-record-direct") orelse unreachable;
    var frame_facts: facts.RouteFrameFacts = measured.*;
    frame_facts.descriptor_id = plan.contract.descriptor_id;
    return .{
        .facts = .{
            .route_id = measured.route_id,
            .descriptor_id = plan.contract.descriptor_id,
            .contract = plan.contract,
            .frame_facts = frame_facts,
            .fragments = &direct_fragments,
            .golden_wat = direct_template,
        },
        .canonical_wit_hash = plan.contract.descriptor_hash orelse "",
    };
}

test "producer shared emitter pilot preserves direct route bytes" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    const old_wat = try producer.emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(old_wat);
    const pilot_wat = try producer.emit_component_wat_pilot(std.testing.allocator, plan);
    defer std.testing.allocator.free(pilot_wat);
    try std.testing.expectEqualSlices(u8, old_wat, pilot_wat);
}

test "producer shared emitter pilot rejects a wrong route id" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    input.facts.route_id = "other-route";
    try std.testing.expectError(error.InvalidIdentity, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects a descriptor mismatch" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    input.facts.descriptor_id = "other-descriptor";
    try std.testing.expectError(error.InvalidIdentity, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects an empty or mismatched hash" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    input.canonical_wit_hash = "";
    try std.testing.expectError(error.InvalidHash, emitter.emit_pilot_wat(std.testing.allocator, input));
    input.canonical_wit_hash = "wrong-hash";
    try std.testing.expectError(error.InvalidHash, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects mutated frame facts" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    input.facts.frame_facts.frame_size = 64;
    try std.testing.expectError(error.InvalidMap, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects invalid lifecycle and fragment tables" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    input.facts.frame_facts.lifecycle = &.{};
    try std.testing.expectError(error.InvalidMap, emitter.emit_pilot_wat(std.testing.allocator, input));

    input = pilot_input(plan);
    input.facts.fragments = &.{};
    try std.testing.expectError(error.InvalidFragments, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects changed golden bytes" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    var changed = try std.testing.allocator.dupe(u8, direct_template);
    defer std.testing.allocator.free(changed);
    changed[0] = 'X';
    input.facts.golden_wat = changed;
    try std.testing.expectError(error.ByteParityMismatch, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects ARC runtime markers" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    var changed = try std.testing.allocator.dupe(u8, direct_template);
    defer std.testing.allocator.free(changed);
    std.mem.copyForwards(u8, changed[0..6], "__arc_");
    input.facts.golden_wat = changed;
    try std.testing.expectError(error.ArcRuntimeMarker, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects a canonical boundary GC reference" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var input = pilot_input(plan);
    var changed = try std.testing.allocator.dupe(u8, direct_template);
    defer std.testing.allocator.free(changed);
    std.mem.copyForwards(u8, changed[0..9], "(ref null");
    input.facts.golden_wat = changed;
    try std.testing.expectError(error.CanonicalGcReference, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot rejects GC opcodes and types but ignores plain text" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    const gc_tokens = [_][]const u8{
        "ref.null",
        "i31ref",
        "i31.new",
        "i31.get_s",
        "i31.get_u",
        "ref.i31",
        "ref.cast",
        "ref.is_null",
        "(ref null $ticket)",
        "struct.new",
        "struct.get_s",
        "struct.get_u",
        "array.new",
        "array.new_fixed",
        "array.new_data",
        "array.new_elem",
        "array.init_data",
        "array.init_elem",
        "array.fill",
        "array.get_s",
        "array.get_u",
        "call_ref",
        "return_call_ref",
        "br_on_cast",
    };
    for (gc_tokens) |token| {
        var changed = try std.testing.allocator.dupe(u8, direct_template);
        defer std.testing.allocator.free(changed);
        std.mem.copyForwards(u8, changed[0..token.len], token);
        changed[token.len] = '\n';
        var input = pilot_input(plan);
        input.facts.golden_wat = changed;
        try std.testing.expectError(error.CanonicalGcReference, emitter.emit_pilot_wat(std.testing.allocator, input));
    }

    var plain_text = try std.testing.allocator.dupe(u8, direct_template);
    defer std.testing.allocator.free(plain_text);
    const comment = ";; ref.null is ordinary text\n";
    std.mem.copyForwards(u8, plain_text[0..comment.len], comment);
    var input = pilot_input(plan);
    input.facts.golden_wat = plain_text;
    try std.testing.expectError(error.ByteParityMismatch, emitter.emit_pilot_wat(std.testing.allocator, input));

    var plain_token = try std.testing.allocator.dupe(u8, direct_template);
    defer std.testing.allocator.free(plain_token);
    const ordinary = "pref.null;; ordinary text\n";
    std.mem.copyForwards(u8, plain_token[0..ordinary.len], ordinary);
    input = pilot_input(plan);
    input.facts.golden_wat = plain_token;
    try std.testing.expectError(error.ByteParityMismatch, emitter.emit_pilot_wat(std.testing.allocator, input));

    var lone_semicolon = try std.testing.allocator.dupe(u8, direct_template);
    defer std.testing.allocator.free(lone_semicolon);
    const ordinary_semicolon = "plain;text\n";
    std.mem.copyForwards(u8, lone_semicolon[0..ordinary_semicolon.len], ordinary_semicolon);
    input = pilot_input(plan);
    input.facts.golden_wat = lone_semicolon;
    try std.testing.expectError(error.ByteParityMismatch, emitter.emit_pilot_wat(std.testing.allocator, input));

    var adjacent = try std.testing.allocator.dupe(u8, direct_template);
    defer std.testing.allocator.free(adjacent);
    const adjacent_token = "ref.null;; ordinary text\n";
    std.mem.copyForwards(u8, adjacent[0..adjacent_token.len], adjacent_token);
    input = pilot_input(plan);
    input.facts.golden_wat = adjacent;
    try std.testing.expectError(error.CanonicalGcReference, emitter.emit_pilot_wat(std.testing.allocator, input));
}

test "producer shared emitter pilot adapter rejects non-direct source and sink shapes" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;
    var changed = plan;
    changed.contract.source.import_name = "other";
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.contract.sink.member = "other";
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));
}

test "producer shared emitter pilot adapter rejects mutated measured plan facts" {
    var context = try PlanContext.init();
    defer context.deinit();
    const plan = context.plan;

    var changed = plan;
    changed.descriptor.wit.world = "other";
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.layout.alignment = 8;
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.producer.stream_capacity = 2;
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.producer.terminal = "other";
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.contract.terminal.close_action = "other";
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    var source_fields = [_]p3_async_manifest.RecordSourceField{changed.layout.source_fields[0]};
    source_fields[0].storage = &.{"other"};
    changed.layout.source_fields = &source_fields;
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    var leaves = [_]@TypeOf(changed.contract.ownership.leaves[0]){changed.contract.ownership.leaves[0]};
    leaves[0].absence_sentinel = 1;
    changed.contract.ownership.leaves = &leaves;
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.contract.producer_core_params = &.{"i32"};
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.descriptor.canonical.record_list_layout = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_stride = 4,
        .max_items = 1,
    };
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    changed.descriptor.canonical.parameterized_owned_record_pair_producer = .{
        .source_module = "source",
        .source_import_name = "make-ticket",
        .source_core_params = &.{"i32"},
        .source_core_results = &.{"i32"},
        .resource_drop_import = "drop",
        .stream_capacity = 1,
        .terminal = "task-return",
        .runtime_mode_param = "u32",
        .left_seed_param = "i32",
        .right_seed_param = "i32",
        .producer_core_params = &.{"i32"},
        .producer_core_results = &.{"i32"},
    };
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));

    changed = plan;
    var mutated_layout = changed.layout;
    mutated_layout.alignment = 8;
    changed.descriptor.canonical.record_layout = mutated_layout;
    changed.layout = mutated_layout;
    changed.contract.payload = .{ .record = mutated_layout };
    try std.testing.expectError(error.InvalidAdmission, producer.emit_component_wat_pilot(std.testing.allocator, changed));
}
