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
