const std = @import("std");
const p3_async_manifest = @import("p3_async_manifest.zig");
const contract = @import("codegen_component_producer_contract.zig");

fn source_contract() contract.SourceContract {
    return .{
        .module = "source@0.1.0",
        .import_name = "make-ticket",
        .core_params = &.{ "i32" },
        .core_results = &.{ "i32" },
    };
}

fn sink_contract() contract.SinkContract {
    return .{
        .module = "sink@0.1.0",
        .member = "consume-via-stream",
        .capacity = 1,
        .read_import = "[async-lower][stream-read-0]consume-via-stream",
        .write_import = "[async-lower][stream-write-0]consume-via-stream",
        .drop_import = "[stream-drop-readable-0]consume-via-stream",
    };
}

fn terminal_contract() contract.TerminalContract {
    return .{
        .close_action = "close",
        .abort_action = "abort",
        .cancel_action = "cancel",
        .cleanup_order = &.{ .resource, .list, .stream, .future, .subtask, .waitable, .frame },
    };
}

fn record_layout(name: []const u8, fields: []const p3_async_manifest.RecordField) p3_async_manifest.RecordLayout {
    return .{
        .name = name,
        .byte_size = @intCast(fields.len * 4),
        .fields = fields,
        .source_fields = &.{},
    };
}

fn base_contract(
    payload: contract.PayloadLayout,
    leaves: []const contract.OwnershipLeaf,
    parents: []const contract.OwnershipParent,
) contract.ProducerContract {
    return .{
        .descriptor_id = "do:test-producer@0.1.0/consume-via-stream",
        .source = source_contract(),
        .sink = sink_contract(),
        .payload = payload,
        .ownership = .{
            .leaves = leaves,
            .parents = parents,
            .complete_write_required = true,
            .pre_transfer_reverse_order = true,
        },
        .terminal = terminal_contract(),
    };
}

fn registry() !p3_async_manifest.Registry {
    return p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
}

fn converted(
    value: p3_async_manifest.Registry,
    locator: []const u8,
) anyerror!contract.ProducerContract {
    const descriptor = value.find(locator, "consume-via-stream") orelse return error.UnsupportedProducerContract;
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedProducerContract;
    return contract.producer_contract_from_shape(descriptor, shape);
}

test "producer contract accepts direct owned record" {
    const fields = [_]p3_async_manifest.RecordField{
        .{ .name = "ticket", .core_type = "i32", .offset = 0 },
    };
    const path = [_][]const u8{"ticket"};
    const leaves = [_]contract.OwnershipLeaf{
        .{ .path = &path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
    };
    const parents = [_]contract.OwnershipParent{};
    const value = base_contract(.{ .record = record_layout("resource-entry", &fields) }, &leaves, &parents);
    try contract.validate_contract(value);
}

test "producer contract preserves pair and triple reverse ownership order" {
    const fields = [_]p3_async_manifest.RecordField{
        .{ .name = "left", .core_type = "i32", .offset = 0 },
        .{ .name = "middle", .core_type = "i32", .offset = 4 },
        .{ .name = "right", .core_type = "i32", .offset = 8 },
    };
    const left_path = [_][]const u8{"left"};
    const middle_path = [_][]const u8{"middle"};
    const right_path = [_][]const u8{"right"};
    const leaves = [_]contract.OwnershipLeaf{
        .{ .path = &left_path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
        .{ .path = &middle_path, .resource = "ticket", .handle_offset = 4, .drop_import = "[resource-drop]ticket", .bit = 1 },
        .{ .path = &right_path, .resource = "ticket", .handle_offset = 8, .drop_import = "[resource-drop]ticket", .bit = 2 },
    };
    const parents = [_]contract.OwnershipParent{};
    const value = base_contract(.{ .record = record_layout("resource-triple", &fields) }, &leaves, &parents);
    try contract.validate_contract(value);
}

test "producer contract retains nested source path and canonical offset" {
    const fields = [_]p3_async_manifest.RecordField{
        .{ .name = "ticket", .core_type = "i32", .offset = 0 },
    };
    const path = [_][]const u8{ "inner", "ticket" };
    const parent_path = [_][]const u8{"inner"};
    const leaves = [_]contract.OwnershipLeaf{
        .{ .path = &path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
    };
    const parents = [_]contract.OwnershipParent{
        .{ .path = &parent_path, .bit = 1 },
    };
    const value = base_contract(.{ .record = record_layout("outer", &fields) }, &leaves, &parents);
    try contract.validate_contract(value);
}

test "producer contract preserves measured list layout" {
    const value = base_contract(.{ .list = .{
        .pointer_offset = 64,
        .length_offset = 68,
        .element_stride = 4,
        .max_items = 3,
    } }, &.{}, &.{});
    try contract.validate_contract(value);
}

test "producer contract rejects duplicate ownership bits" {
    const path_a = [_][]const u8{"left"};
    const path_b = [_][]const u8{"right"};
    const leaves = [_]contract.OwnershipLeaf{
        .{ .path = &path_a, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
        .{ .path = &path_b, .resource = "ticket", .handle_offset = 4, .drop_import = "[resource-drop]ticket", .bit = 0 },
    };
    const value = base_contract(.{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } }, &leaves, &.{});
    try std.testing.expectError(error.DuplicateOwnershipBit, contract.validate_contract(value));
}

test "producer contract rejects duplicate ownership paths" {
    const path = [_][]const u8{"ticket"};
    const leaves = [_]contract.OwnershipLeaf{
        .{ .path = &path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0 },
        .{ .path = &path, .resource = "ticket", .handle_offset = 4, .drop_import = "[resource-drop]ticket", .bit = 1 },
    };
    const value = base_contract(.{ .scalar = .{ .core_type = "i32", .byte_size = 8, .alignment = 4 } }, &leaves, &.{});
    try std.testing.expectError(error.DuplicateOwnershipPath, contract.validate_contract(value));
}

test "producer contract rejects zero absence sentinel" {
    const path = [_][]const u8{"ticket"};
    const leaves = [_]contract.OwnershipLeaf{
        .{ .path = &path, .resource = "ticket", .handle_offset = 0, .drop_import = "[resource-drop]ticket", .bit = 0, .absence_sentinel = 0 },
    };
    const value = base_contract(.{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } }, &leaves, &.{});
    try std.testing.expectError(error.ZeroHandleAbsenceSentinel, contract.validate_contract(value));
}

test "producer contract rejects missing drop import" {
    const path = [_][]const u8{"ticket"};
    const leaves = [_]contract.OwnershipLeaf{
        .{ .path = &path, .resource = "ticket", .handle_offset = 0, .drop_import = "", .bit = 0 },
    };
    const value = base_contract(.{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } }, &leaves, &.{});
    try std.testing.expectError(error.MissingDropImport, contract.validate_contract(value));
}

test "producer contract rejects transfer before complete write" {
    const value = base_contract(.{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } }, &.{}, &.{});
    var invalid = value;
    invalid.ownership.complete_write_required = false;
    try std.testing.expectError(error.TransferBeforeCompleteWrite, contract.validate_contract(invalid));
}

test "producer contract rejects parent cleanup before child" {
    var value = base_contract(.{ .scalar = .{ .core_type = "i32", .byte_size = 4, .alignment = 4 } }, &.{}, &.{});
    value.terminal.cleanup_order = &.{ .frame, .waitable, .stream, .future, .subtask, .list, .resource };
    try std.testing.expectError(error.ParentCleanupBeforeChild, contract.validate_contract(value));
}

test "producer contract conversion admits every registered producer shape" {
    var loaded = try registry();
    defer loaded.deinit(std.testing.allocator);

    const locators = [_][]const u8{
        "do:g6-2-owned-record-producer@0.1.0",
        "do:g6-2-owned-record-pair-producer@0.1.0",
        "do:g6-2-owned-record-triple-producer@0.1.0",
        "do:g6-2-owned-record-nested-producer@0.1.0",
        "do:g6-2-owned-record-pair-parameterized-producer@0.1.0",
        "do:g6-2-c-min-producer@0.1.0",
        "do:g6-2-c-min-dynamic-producer@0.1.0",
        "do:g6-2-batched-list-producer@0.1.0",
        "do:g6-2-scalar-list-producer@0.1.0",
    };
    for (locators) |locator| {
        const descriptor = loaded.find(locator, "consume-via-stream") orelse return error.TestUnexpectedResult;
        const shape = p3_async_manifest.lowering_shape(descriptor) orelse return error.TestUnexpectedResult;
        const value = try contract.producer_contract_from_shape(descriptor, shape);
        try contract.validate_contract(value);
        try std.testing.expectEqualStrings(locator, value.descriptor_id);
        try std.testing.expectEqualStrings(descriptor.wit_sha256.?, value.descriptor_hash.?);
        try std.testing.expectEqual(@as(u32, 1), value.sink.capacity);
        try std.testing.expectEqualStrings(descriptor.canonical.async_import_module, value.sink.module);
        try std.testing.expectEqualStrings(descriptor.member, value.sink.member);
    }
}

test "producer contract conversion preserves direct pair and triple ownership facts" {
    var loaded = try registry();
    defer loaded.deinit(std.testing.allocator);

    const pair = try converted(loaded, "do:g6-2-owned-record-pair-producer@0.1.0");
    try std.testing.expectEqual(@as(usize, 2), pair.ownership.leaves.len);
    try std.testing.expectEqualStrings("left", pair.ownership.leaves[0].path[0]);
    try std.testing.expectEqual(@as(u32, 0), pair.ownership.leaves[0].handle_offset);
    try std.testing.expectEqual(@as(u8, 0), pair.ownership.leaves[0].bit);
    try std.testing.expectEqualStrings("right", pair.ownership.leaves[1].path[0]);
    try std.testing.expectEqual(@as(u32, 4), pair.ownership.leaves[1].handle_offset);
    try std.testing.expectEqual(@as(u8, 1), pair.ownership.leaves[1].bit);

    const triple = try converted(loaded, "do:g6-2-owned-record-triple-producer@0.1.0");
    try std.testing.expectEqual(@as(usize, 3), triple.ownership.leaves.len);
    try std.testing.expectEqualStrings("left", triple.ownership.leaves[0].path[0]);
    try std.testing.expectEqualStrings("middle", triple.ownership.leaves[1].path[0]);
    try std.testing.expectEqualStrings("right", triple.ownership.leaves[2].path[0]);
    try std.testing.expectEqual(@as(u32, 8), triple.ownership.leaves[2].handle_offset);
}

test "producer contract conversion preserves nested and list facts" {
    var loaded = try registry();
    defer loaded.deinit(std.testing.allocator);

    const nested = try converted(loaded, "do:g6-2-owned-record-nested-producer@0.1.0");
    try std.testing.expectEqual(@as(usize, 1), nested.ownership.leaves.len);
    try std.testing.expectEqual(@as(usize, 2), nested.ownership.leaves[0].path.len);
    try std.testing.expectEqualStrings("inner", nested.ownership.leaves[0].path[0]);
    try std.testing.expectEqualStrings("ticket", nested.ownership.leaves[0].path[1]);
    try std.testing.expectEqual(@as(usize, 1), nested.ownership.parents.len);
    try std.testing.expectEqualStrings("inner", nested.ownership.parents[0].path[0]);
    try std.testing.expectEqual(@as(u32, 0), nested.ownership.leaves[0].handle_offset);

    const list = try converted(loaded, "do:g6-2-c-min-producer@0.1.0");
    switch (list.payload) {
        .list => |layout| {
            try std.testing.expectEqual(@as(u32, 64), layout.pointer_offset);
            try std.testing.expectEqual(@as(u32, 68), layout.length_offset);
            try std.testing.expectEqual(@as(u32, 4), layout.element_stride);
            try std.testing.expectEqual(@as(u32, 3), layout.max_items);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), list.ownership.leaves.len);
    try std.testing.expectEqual(@as(usize, 1), list.ownership.parents.len);
}

test "producer contract conversion preserves dynamic, batched, scalar-list, and parameterized facts" {
    var loaded = try registry();
    defer loaded.deinit(std.testing.allocator);

    const dynamic = try converted(loaded, "do:g6-2-c-min-dynamic-producer@0.1.0");
    try std.testing.expectEqualStrings("u32", dynamic.runtime_count_param.?);
    try std.testing.expectEqual(@as(u32, 3), dynamic.runtime_max.?);

    const batched = try converted(loaded, "do:g6-2-batched-list-producer@0.1.0");
    try std.testing.expectEqual(@as(u32, 2), batched.batch_count.?);
    try std.testing.expectEqualSlices(u32, &.{ 2, 1 }, batched.batch_lengths);

    const scalar = try converted(loaded, "do:g6-2-scalar-list-producer@0.1.0");
    try std.testing.expectEqualStrings("u32", scalar.runtime_count_param.?);
    try std.testing.expectEqual(@as(usize, 0), scalar.ownership.leaves.len);

    const parameterized = try converted(loaded, "do:g6-2-owned-record-pair-parameterized-producer@0.1.0");
    try std.testing.expectEqualStrings("u32", parameterized.runtime_mode_param.?);
    try std.testing.expectEqualStrings("u32", parameterized.left_seed_param.?);
    try std.testing.expectEqualStrings("u32", parameterized.right_seed_param.?);
    try std.testing.expectEqual(@as(usize, 3), parameterized.producer_core_params.len);
}

test "producer contract conversion rejects variant and non-producer shapes" {
    var loaded = try registry();
    defer loaded.deinit(std.testing.allocator);

    const variant_descriptor = loaded.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse
        return error.TestUnexpectedResult;
    const variant_shape = p3_async_manifest.lowering_shape(variant_descriptor) orelse return error.TestUnexpectedResult;
    try std.testing.expectError(
        error.UnsupportedProducerContract,
        contract.producer_contract_from_shape(variant_descriptor, variant_shape),
    );

    const non_producer = loaded.find("do:record-stream-probe@0.1.0", "read-via-stream") orelse
        return error.TestUnexpectedResult;
    const non_producer_shape = p3_async_manifest.lowering_shape(non_producer) orelse return error.TestUnexpectedResult;
    try std.testing.expectError(
        error.UnsupportedProducerContract,
        contract.producer_contract_from_shape(non_producer, non_producer_shape),
    );
}

test "producer contract conversion rejects borrowed and malformed nested facts" {
    var loaded = try registry();
    defer loaded.deinit(std.testing.allocator);

    const descriptor = loaded.find("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream") orelse
        return error.TestUnexpectedResult;
    var borrowed_field = descriptor.canonical.record_layout.?.source_fields[0];
    borrowed_field.ownership = .borrow;
    var borrowed_sources = [_]p3_async_manifest.RecordSourceField{borrowed_field};
    var borrowed_layout = descriptor.canonical.record_layout.?;
    borrowed_layout.source_fields = &borrowed_sources;
    const borrowed_shape = p3_async_manifest.OwnedRecordStreamProducerShape{
        .element = "resource-entry",
        .stream_index = 0,
        .method = .{
            .import_name = descriptor.canonical.async_import_name,
            .core_params = descriptor.canonical.core_params,
            .core_results = descriptor.canonical.core_results,
        },
        .stream = descriptor.canonical.stream.?,
        .record_layout = borrowed_layout,
        .producer = descriptor.canonical.producer.?,
    };
    try std.testing.expectError(
        error.UnsupportedProducerContract,
        contract.producer_contract_from_shape(descriptor, .{ .owned_record_stream_producer = borrowed_shape }),
    );

    const nested_descriptor = loaded.find("do:g6-2-owned-record-nested-producer@0.1.0", "consume-via-stream") orelse
        return error.TestUnexpectedResult;
    var nested_shape = switch (p3_async_manifest.lowering_shape(nested_descriptor) orelse return error.TestUnexpectedResult) {
        .record_resource_nested_stream_producer => |value| value,
        else => return error.TestUnexpectedResult,
    };
    var nested_source = nested_shape.record_layout.source_fields[0];
    var nested_leaf = nested_source.nested_fields[0];
    nested_leaf.name = "wrong";
    var nested_leaves = [_]p3_async_manifest.RecordNestedField{nested_leaf};
    nested_source.nested_fields = &nested_leaves;
    var nested_sources = [_]p3_async_manifest.RecordSourceField{nested_source};
    nested_shape.record_layout.source_fields = &nested_sources;
    try std.testing.expectError(
        error.UnsupportedProducerContract,
        contract.producer_contract_from_shape(
            nested_descriptor,
            .{ .record_resource_nested_stream_producer = nested_shape },
        ),
    );
}

test "producer contract conversion rejects a seventh nested level" {
    var loaded = try registry();
    defer loaded.deinit(std.testing.allocator);

    const descriptor = loaded.find("do:g6-2-owned-record-nested-producer@0.1.0", "consume-via-stream") orelse
        return error.TestUnexpectedResult;
    var shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_resource_nested_stream_producer => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const leaf = shape.record_layout.source_fields[0].nested_fields[0];
    var level_6 = [_]p3_async_manifest.RecordNestedField{leaf};
    var level_5 = [_]p3_async_manifest.RecordNestedField{.{ .name = "ticket", .source_type = "inner", .storage = &.{}, .nested_fields = &level_6 }};
    var level_4 = [_]p3_async_manifest.RecordNestedField{.{ .name = "ticket", .source_type = "inner", .storage = &.{}, .nested_fields = &level_5 }};
    var level_3 = [_]p3_async_manifest.RecordNestedField{.{ .name = "ticket", .source_type = "inner", .storage = &.{}, .nested_fields = &level_4 }};
    var level_2 = [_]p3_async_manifest.RecordNestedField{.{ .name = "ticket", .source_type = "inner", .storage = &.{}, .nested_fields = &level_3 }};
    var level_1 = [_]p3_async_manifest.RecordNestedField{.{ .name = "ticket", .source_type = "inner", .storage = &.{}, .nested_fields = &level_2 }};
    var outer = shape.record_layout.source_fields[0];
    outer.nested_fields = &level_1;
    var sources = [_]p3_async_manifest.RecordSourceField{outer};
    shape.record_layout.source_fields = &sources;

    try std.testing.expectError(
        error.UnsupportedProducerContract,
        contract.producer_contract_from_shape(
            descriptor,
            .{ .record_resource_nested_stream_producer = shape },
        ),
    );
}
