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

test "synchronous GC adapter fails closed for managed values without an emitted layout" {
    try std.testing.expectError(error.UnsupportedGcSyncType, adapter.classify_admitted_type("[u32]", &.{}));
    try std.testing.expectError(error.UnsupportedGcSyncType, adapter.classify_admitted_type("Tuple<text,[u8]>", &.{}));

    const fields = [_]representation.StructFieldShape{
        .{ .name = "value", .ty = "[u8]" },
    };
    const structs = [_]representation.StructShape{
        .{ .name = "Box", .fields = fields[0..] },
    };
    try std.testing.expectError(error.UnsupportedGcSyncType, adapter.classify_admitted_type("Box", structs[0..]));
}
