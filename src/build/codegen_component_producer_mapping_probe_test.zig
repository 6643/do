const std = @import("std");
const facts = @import("codegen_component_producer_facts.zig");
const probe = @import("codegen_component_producer_mapping_probe.zig");

const valid_fields = [_]probe.FrameFact{
    .{ .name = "result-tag", .offset = 0, .width = 4, .alignment = 4, .role = .result_tag },
    .{ .name = "payload", .offset = 4, .width = 4, .alignment = 4, .role = .payload },
};

const valid_ownership = [_]probe.OwnershipFact{
    .{
        .name = "record",
        .encoding = .scalar,
        .state_offset = 8,
        .guest_value = 1,
        .transferred_value = 2,
        .released_value = 3,
    },
};

const valid_bindings = [_]probe.BindingFact{
    .{ .name = "payload", .canonical_offset = 0, .payload_size = 4, .frame_offset = 4, .width = 4 },
};

const valid_lifecycle = [_]probe.LifecycleFact{
    .{
        .name = "record-lifecycle",
        .required_text = &.{ "[producer-record-transfer]", "[producer-child-before-parent-cleanup]" },
        .ordered_anchors = &.{ "[producer-record-transfer]", "[producer-child-before-parent-cleanup]" },
    },
};

fn valid_fact() probe.TemplateFact {
    return .{
        .route_id = "test-route",
        .template_name = "test.wat",
        .frame_size = 16,
        .frames = &valid_fields,
        .ownership = &valid_ownership,
        .bindings = &valid_bindings,
        .lifecycle = &valid_lifecycle,
    };
}

test "producer canonical frame probe accepts a valid fact table entry" {
    const report = try probe.validate_facts(valid_fact());
    try std.testing.expectEqualStrings("test-route", report.route_id);
    try std.testing.expectEqual(@as(usize, 2), report.frame_count);
    try std.testing.expectEqual(@as(usize, 1), report.binding_count);
}

test "producer canonical frame probe rejects an empty route" {
    var fact = valid_fact();
    fact.route_id = "";
    try std.testing.expectError(error.InvalidIdentity, probe.validate_facts(fact));
}

test "producer canonical frame probe rejects overlapping frame fields" {
    var fields = valid_fields;
    fields[1].offset = 0;
    var fact = valid_fact();
    fact.frames = &fields;
    try std.testing.expectError(error.FrameOverlap, probe.validate_facts(fact));
}

test "producer canonical frame probe shares zero-offset identity" {
    comptime {
        if (@TypeOf(probe.FrameFact) != @TypeOf(facts.FrameFact) or
            @TypeOf(probe.BindingFact) != @TypeOf(facts.CanonicalBinding) or
            @TypeOf(probe.TemplateFact) != @TypeOf(facts.RouteFrameFacts))
        {
            @compileError("mapping probe facts must alias production facts");
        }
    }
    const fields = [_]facts.FrameFact{.{ .name = "tag", .offset = 0, .width = 4, .alignment = 4, .role = .result_tag }};
    const ownership = [_]facts.OwnershipFact{.{ .name = "state", .encoding = .scalar, .state_offset = 0, .guest_value = 1, .transferred_value = 2, .released_value = 3 }};
    const bindings = [_]facts.CanonicalBinding{.{ .name = "payload", .canonical_offset = 0, .payload_size = 4, .frame_offset = 4, .width = 4 }};
    const lifecycle = [_]facts.LifecycleAnchor{.{ .name = "life", .required_text = &.{"life"}, .ordered_anchors = &.{"life"} }};
    const route = facts.RouteFrameFacts{ .route_id = "zero", .descriptor_id = "descriptor", .frame_size = 8, .frames = &fields, .ownership = &ownership, .bindings = &bindings, .lifecycle = &lifecycle };
    const production_report = try facts.validate(route);
    const probe_report = try probe.validate_facts(route);
    try std.testing.expectEqual(production_report, probe_report);

    var mutated_bindings = bindings;
    mutated_bindings[0].width = 5;
    var mutated = route;
    mutated.bindings = &mutated_bindings;
    try std.testing.expectError(error.BindingOutsidePayload, facts.validate_route_facts(mutated));
    try std.testing.expectError(error.BindingOutsidePayload, probe.validate_facts(mutated));
}

test "producer canonical frame probe requires production descriptor identity" {
    var fact = valid_fact();
    try std.testing.expectError(error.InvalidIdentity, facts.validate_route_facts(fact));
    fact.descriptor_id = "descriptor";
    try facts.validate_route_facts(fact);
}

test "producer canonical frame probe rejects canonical binding overlap" {
    const second = [_]facts.CanonicalBinding{
        .{ .name = "first", .canonical_offset = 0, .payload_size = 8, .frame_offset = 8, .width = 4 },
        .{ .name = "second", .canonical_offset = 2, .payload_size = 8, .frame_offset = 12, .width = 4 },
    };
    var fact = valid_fact();
    fact.bindings = &second;
    try std.testing.expectError(error.BindingOverlap, facts.validate_route_facts(.{
        .route_id = fact.route_id,
        .descriptor_id = "descriptor",
        .frame_size = 32,
        .frames = fact.frames,
        .ownership = fact.ownership,
        .bindings = fact.bindings,
        .lifecycle = fact.lifecycle,
    }));
    try std.testing.expectError(error.BindingOverlap, probe.validate_facts(.{
        .route_id = fact.route_id,
        .template_name = fact.template_name,
        .frame_size = 32,
        .frames = fact.frames,
        .ownership = fact.ownership,
        .bindings = fact.bindings,
        .lifecycle = fact.lifecycle,
    }));
}

test "producer canonical frame probe rejects overlapping bindings" {
    var bindings = valid_bindings;
    bindings[0].frame_offset = 14;
    var fact = valid_fact();
    fact.bindings = &bindings;
    try std.testing.expectError(error.BindingOutsideFrame, probe.validate_facts(fact));
}

test "producer canonical frame probe rejects an invalid ownership encoding" {
    var ownership = valid_ownership;
    ownership[0].transferred_value = ownership[0].guest_value;
    var fact = valid_fact();
    fact.ownership = &ownership;
    try std.testing.expectError(error.InvalidOwnership, probe.validate_facts(fact));
}

test "producer canonical frame probe has twelve checked-in template facts" {
    try std.testing.expectEqual(@as(usize, 12), probe.checked_in_template_facts.len);

    for (probe.checked_in_template_facts, 0..) |fact, index| {
        _ = try probe.validate_facts(fact);
        try std.testing.expectEqual(@as(u32, 128), fact.frame_size);
        try std.testing.expect(fact.markers.len != 0);
        for (probe.checked_in_template_facts[0..index]) |prior| {
            try std.testing.expect(!std.mem.eql(u8, prior.route_id, fact.route_id));
            try std.testing.expect(!std.mem.eql(u8, prior.template_name, fact.template_name));
        }
    }
}

test "producer canonical frame probe preserves route-specific fact shapes" {
    const record = probe.fact_for_route("owned-record-direct") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(probe.OwnershipEncoding.scalar, record.ownership[0].encoding);
    try std.testing.expectEqual(@as(usize, 1), record.bindings.len);

    const pair = probe.fact_for_route("owned-record-pair") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(probe.OwnershipEncoding.mask, pair.ownership[0].encoding);
    try std.testing.expectEqual(@as(u32, 3), pair.ownership[0].guest_value);
    try std.testing.expectEqual(@as(usize, 2), pair.bindings.len);

    const batch = probe.fact_for_route("c-min-batched-list") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(probe.OwnershipEncoding.batched_scalar, batch.ownership[0].encoding);
    try std.testing.expectEqual(@as(usize, 2), batch.ownership.len);
    try std.testing.expectEqual(@as(usize, 4), batch.bindings.len);
}

test "producer canonical frame probe looks up an unknown route as missing" {
    try std.testing.expect(probe.fact_for_route("missing-route") == null);
}

const checked_in_templates = [_]struct {
    route_id: []const u8,
    bytes: []const u8,
}{
    .{ .route_id = "owned-record-direct", .bytes = @embedFile("owned_record_stream_producer_template.wat") },
    .{ .route_id = "owned-record-list", .bytes = @embedFile("list_owned_record_stream_producer_template.wat") },
    .{ .route_id = "owned-record-two-list", .bytes = @embedFile("two_list_owned_record_stream_producer_template.wat") },
    .{ .route_id = "owned-record-pair", .bytes = @embedFile("owned_record_pair_stream_producer_template.wat") },
    .{ .route_id = "owned-record-triple", .bytes = @embedFile("owned_record_triple_stream_producer_template.wat") },
    .{ .route_id = "owned-record-nested", .bytes = @embedFile("owned_record_nested_stream_producer_template.wat") },
    .{ .route_id = "owned-record-mixed", .bytes = @embedFile("mixed_owned_record_stream_producer_template.wat") },
    .{ .route_id = "owned-record-parameterized-pair", .bytes = @embedFile("parameterized_owned_record_pair_stream_producer_template.wat") },
    .{ .route_id = "c-min-list", .bytes = @embedFile("cmin_list_resource_producer_template.wat") },
    .{ .route_id = "c-min-dynamic-list", .bytes = @embedFile("cmin_dynamic_list_resource_producer_template.wat") },
    .{ .route_id = "scalar-list", .bytes = @embedFile("cmin_scalar_list_stream_producer_template.wat") },
    .{ .route_id = "c-min-batched-list", .bytes = @embedFile("cmin_batched_list_resource_producer_template.wat") },
};

test "producer canonical frame probe decomposes every checked-in template" {
    for (checked_in_templates) |entry| {
        const fact = probe.fact_for_route(entry.route_id) orelse return error.TestUnexpectedResult;
        const observation = try probe.decompose_template(entry.bytes, fact.*);
        try std.testing.expectEqualStrings(entry.route_id, observation.route_id);
        try std.testing.expectEqual(fact.markers.len, observation.marker_count);
        try std.testing.expectEqual(fact.lifecycle.len, observation.lifecycle_count);
        try std.testing.expect(observation.first_anchor_offset < observation.last_anchor_offset);
    }
}

test "producer canonical frame probe reports a missing marker" {
    const markers = [_]probe.MarkerFact{.{ .name = "producer-required" }};
    const lifecycle = [_]probe.LifecycleFact{.{
        .name = "lifecycle",
        .required_text = &.{"(func $start"},
        .ordered_anchors = &.{"(func $start"},
    }};
    const fact = probe.TemplateFact{
        .route_id = "synthetic",
        .template_name = "synthetic.wat",
        .frame_size = 16,
        .frames = &valid_fields,
        .ownership = &valid_ownership,
        .bindings = &valid_bindings,
        .lifecycle = &lifecycle,
        .markers = &markers,
    };
    try std.testing.expectError(error.MissingMarker, probe.decompose_template("(func $start)", fact));
}

test "producer canonical frame probe reports lifecycle order drift" {
    const markers = [_]probe.MarkerFact{.{ .name = "producer-required" }};
    const lifecycle = [_]probe.LifecycleFact{.{
        .name = "lifecycle",
        .required_text = &.{ "[producer-required]", "(func $start", "(func $finish" },
        .ordered_anchors = &.{ "(func $start", "(func $finish" },
    }};
    const fact = probe.TemplateFact{
        .route_id = "synthetic",
        .template_name = "synthetic.wat",
        .frame_size = 16,
        .frames = &valid_fields,
        .ownership = &valid_ownership,
        .bindings = &valid_bindings,
        .lifecycle = &lifecycle,
        .markers = &markers,
    };
    try std.testing.expectError(
        error.LifecycleOrder,
        probe.decompose_template("[producer-required]\n(func $finish)\n(func $start)", fact),
    );
}

test "producer canonical frame probe preserves canonical prefix and suffix" {
    const canonical = "(module\n  (func $body)\n)";
    const generated = "(module\n  (func $body)\n  ;; route metadata\n)";
    const observation = try probe.verify_canonical_segments(canonical, generated);
    try std.testing.expectEqual(@as(usize, 2), observation.canonical_suffix_len);
    try std.testing.expect(observation.insertion_len != 0);
}

test "producer canonical frame probe rejects canonical byte drift" {
    const canonical = "(module\n  (func $body)\n)";
    try std.testing.expectError(
        error.CanonicalParity,
        probe.verify_canonical_segments("(module\n  (func $body!)\n)", canonical),
    );
    try std.testing.expectError(
        error.CanonicalParity,
        probe.verify_canonical_segments(canonical, "(module\n  (func $body)\n!"),
    );
}

test "producer canonical frame probe rejects a duplicate canonical segment" {
    const canonical = "(module\n  (func $body)\n)";
    const generated = "(module\n  (func $body)\n)\n;; duplicate\n(module\n  (func $body)\n)";
    try std.testing.expectError(error.DuplicateCanonicalSegment, probe.verify_canonical_segments(canonical, generated));
}

test "producer canonical frame probe rejects batched pointer alias" {
    const batch = probe.fact_for_route("c-min-batched-list") orelse return error.TestUnexpectedResult;
    var bindings = [_]probe.BindingFact{
        batch.bindings[0], batch.bindings[1], batch.bindings[2], batch.bindings[3],
    };
    bindings[2].frame_offset = bindings[0].frame_offset;
    var mutated = batch.*;
    mutated.bindings = &bindings;
    try std.testing.expectError(error.BindingOverlap, probe.validate_facts(mutated));
}

test "producer canonical frame probe rejects batched cleanup order drift" {
    const batch = probe.fact_for_route("c-min-batched-list") orelse return error.TestUnexpectedResult;
    var lifecycle = [_]probe.LifecycleFact{batch.lifecycle[0]};
    const reordered = [_][]const u8{ "(func $batch-transfer", "(func $batch-release", "(func $cleanup-batched" };
    lifecycle[0].ordered_anchors = &reordered;
    var mutated = batch.*;
    mutated.lifecycle = &lifecycle;
    try std.testing.expectError(
        error.LifecycleOrder,
        probe.decompose_template(@embedFile("cmin_batched_list_resource_producer_template.wat"), mutated),
    );
}
