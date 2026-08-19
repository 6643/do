const std = @import("std");
const adapter = @import("codegen_gc_sync_adapter.zig");
const representation = @import("codegen_gc_representation.zig");

test "synchronous GC adapter admits only emitted managed leaf layouts" {
    const text = try adapter.classify_admitted_type("text", &.{});
    try std.testing.expectEqual(representation.ValueRep.gc_managed, text.rep);
    try std.testing.expectEqualStrings("(ref null $do_text)", text.wasm_type);

    const bytes = try adapter.classify_admitted_type("[u8]", &.{});
    try std.testing.expectEqual(representation.ValueRep.gc_managed, bytes.rep);
    try std.testing.expectEqualStrings("(ref null $do_bytes)", bytes.wasm_type);
}

test "synchronous GC adapter admits the registered tuple carrier and rejects other unregistered aggregates" {
    const words = try adapter.classify_admitted_type("[u32]", &.{});
    try std.testing.expectEqual(representation.ValueRep.gc_managed, words.rep);
    try std.testing.expectEqualStrings("(ref null $do_u32)", words.wasm_type);

    const tuple = try adapter.classify_admitted_type("Tuple<text,[u8]>", &.{});
    try std.testing.expectEqual(representation.ValueRep.gc_managed, tuple.rep);
    try std.testing.expectEqualStrings("(ref null $tuple_text_bytes)", tuple.wasm_type);

    const fields = [_]representation.StructFieldShape{
        .{ .name = "value", .ty = "[u8]" },
    };
    const structs = [_]representation.StructShape{
        .{ .name = "Box", .fields = fields[0..] },
    };
    try std.testing.expectError(error.UnsupportedGcSyncType, adapter.classify_admitted_type("Box", structs[0..]));
}

test "synchronous GC adapter classifies managed lists as GC references" {
    const fields = [_]representation.StructFieldShape{
        .{ .name = "value", .ty = "[u8]" },
    };
    const structs = [_]representation.StructShape{
        .{ .name = "Box", .fields = fields[0..] },
    };
    const facts = try adapter.classify_admitted_type("[Box]", structs[0..]);
    try std.testing.expectEqual(representation.ValueRep.gc_managed, facts.rep);
    try std.testing.expect(adapter.is_managed_struct_list_type("[Box]", structs[0..]));
    try std.testing.expect(!adapter.is_managed_struct_list_type("[text]", structs[0..]));
    const texts = try adapter.classify_admitted_type("[text]", structs[0..]);
    try std.testing.expectEqual(representation.ValueRep.gc_managed, texts.rep);
    try std.testing.expect(adapter.is_managed_text_list_type("[text]"));
    try std.testing.expect(adapter.is_managed_list_type("[text]", structs[0..]));
}

test "synchronous GC adapter admits a nested managed list" {
    try std.testing.expect(adapter.is_managed_list_type("[[u8]]", &.{}));
    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);
    try adapter.append_wasm_type_for_with_unions_and_arrays(
        std.testing.allocator,
        &wat,
        "[[u8]]",
        &.{},
        &.{},
        &.{},
        &.{},
    );
    try std.testing.expectEqualStrings("(ref null $do_list_list_u8)", wat.items);
}
