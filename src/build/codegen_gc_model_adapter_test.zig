const std = @import("std");
const model = @import("codegen_model.zig");
const representation = @import("codegen_gc_representation.zig");
const adapter = @import("codegen_gc_model_adapter.zig");

test "model adapter classifies managed struct fields through GC facts" {
    const packet = model.StructDecl{
        .name = "Packet",
        .fields = &[_]model.StructField{
            .{ .name = "bytes", .ty = "[u8]" },
            .{ .name = "version", .ty = "i32" },
        },
        .layout_source = null,
        .tokens = &.{},
    };

    const layout = try adapter.collect_struct_layout(std.testing.allocator, packet, &[_]model.StructDecl{packet}, &.{});
    defer adapter.deinit_struct_layout(std.testing.allocator, layout);

    try std.testing.expectEqualStrings("Packet", layout.name);
    try std.testing.expectEqual(@as(usize, 2), layout.fields.len);
    try std.testing.expectEqualStrings("bytes", layout.fields[0].name);
    try std.testing.expectEqual(representation.ValueRep.gc_managed, layout.fields[0].rep);
    try std.testing.expectEqual(@as(u32, 1), layout.fields[1].field_index);
}

test "model adapter rejects a resource nested in a managed struct" {
    const packet = model.StructDecl{
        .name = "Packet",
        .fields = &[_]model.StructField{
            .{ .name = "file", .ty = "File" },
        },
        .layout_source = null,
        .tokens = &.{},
    };

    try std.testing.expectError(
        error.ResourceInManagedAggregate,
        adapter.collect_struct_layout(std.testing.allocator, packet, &[_]model.StructDecl{packet}, &[_][]const u8{"File"}),
    );
}

test "model adapter preserves nested managed struct classification" {
    const child = model.StructDecl{
        .name = "Child",
        .fields = &[_]model.StructField{.{ .name = "value", .ty = "text" }},
        .layout_source = null,
        .tokens = &.{},
    };
    const parent = model.StructDecl{
        .name = "Parent",
        .fields = &[_]model.StructField{.{ .name = "child", .ty = "Child" }},
        .layout_source = null,
        .tokens = &.{},
    };
    const layout = try adapter.collect_struct_layout(std.testing.allocator, parent, &[_]model.StructDecl{ child, parent }, &.{});
    defer adapter.deinit_struct_layout(std.testing.allocator, layout);

    try std.testing.expectEqual(representation.ValueRep.gc_managed, layout.fields[0].rep);
}
