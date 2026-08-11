const std = @import("std");
const representation = @import("codegen_gc_representation.zig");
const layout = @import("codegen_gc_layout.zig");

test "GC representation classifies inline, managed, and resource values" {
    try std.testing.expectEqual(representation.ValueRep.inline_value, try representation.classify_type("i32", &.{}, &.{}));
    try std.testing.expectEqual(representation.ValueRep.gc_managed, try representation.classify_type("text", &.{}, &.{}));
    try std.testing.expectEqual(representation.ValueRep.gc_managed, try representation.classify_type("[u8]", &.{}, &.{}));
    try std.testing.expectEqual(representation.ValueRep.resource_handle, try representation.classify_type("File", &.{}, &.{"File"}));
}

test "GC representation rejects unknown and resource nested values" {
    try std.testing.expectError(error.UnknownType, representation.classify_type("Missing", &.{}, &.{}));

    const fields = [_]representation.StructFieldShape{
        .{ .name = "file", .ty = "File" },
    };
    const structs = [_]representation.StructShape{
        .{ .name = "Holder", .fields = fields[0..] },
    };
    try std.testing.expectError(error.ResourceInManagedAggregate, representation.classify_type("Holder", structs[0..], &.{"File"}));
}

test "GC representation rejects recursive aggregate shapes" {
    const a_fields = [_]representation.StructFieldShape{
        .{ .name = "next", .ty = "B" },
    };
    const b_fields = [_]representation.StructFieldShape{
        .{ .name = "next", .ty = "A" },
    };
    const structs = [_]representation.StructShape{
        .{ .name = "A", .fields = a_fields[0..] },
        .{ .name = "B", .fields = b_fields[0..] },
    };
    try std.testing.expectError(error.UnsupportedGcAggregate, representation.classify_type("A", structs[0..], &.{}));
}

test "GC layout records managed field indices" {
    const fields = [_]representation.StructFieldShape{
        .{ .name = "value", .ty = "[u8]" },
        .{ .name = "tag", .ty = "i32" },
    };
    const shape = representation.StructShape{ .name = "Box", .fields = fields[0..] };
    const result = try layout.collect_struct_layout(std.testing.allocator, shape, &.{shape}, &.{});
    defer layout.deinit_struct_layout(std.testing.allocator, result);

    try std.testing.expectEqualStrings("Box", result.name);
    try std.testing.expectEqual(@as(usize, 2), result.fields.len);
    try std.testing.expectEqualStrings("value", result.fields[0].name);
    try std.testing.expectEqual(representation.ValueRep.gc_managed, result.fields[0].rep);
    try std.testing.expectEqual(@as(u32, 0), result.fields[0].field_index);
    try std.testing.expectEqual(representation.ValueRep.inline_value, result.fields[1].rep);
    try std.testing.expectEqual(@as(u32, 1), result.fields[1].field_index);
}

test "GC tuple layout records managed leaf fields" {
    const elements = [_][]const u8{ "text", "[u8]" };
    const result = try layout.collect_tuple_layout(std.testing.allocator, "Tuple_text_bytes", elements[0..], &.{}, &.{});
    defer layout.deinit_tuple_layout(std.testing.allocator, result);

    try std.testing.expectEqualStrings("Tuple_text_bytes", result.name);
    try std.testing.expectEqual(@as(usize, 2), result.fields.len);
    try std.testing.expectEqual(representation.ValueRep.gc_managed, result.fields[0].rep);
    try std.testing.expectEqual(representation.ValueRep.gc_managed, result.fields[1].rep);
    try std.testing.expectEqual(@as(u32, 0), result.fields[0].field_index);
    try std.testing.expectEqual(@as(u32, 1), result.fields[1].field_index);
}

test "GC tuple layout rejects nested tuple leaves" {
    const elements = [_][]const u8{ "Tuple<text, [u8]>", "u8" };
    try std.testing.expectError(
        error.UnsupportedGcAggregate,
        layout.collect_tuple_layout(std.testing.allocator, "Nested", elements[0..], &.{}, &.{}),
    );
}
