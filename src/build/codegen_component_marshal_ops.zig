//! Ordered synchronous canonical-memory operations.
//!
//! This module is deliberately an execution-independent boundary. It turns a
//! measured marshal tree into a fixed operation order and validates arithmetic
//! used by a future WAT emitter. It does not emit WAT, access memory, or run a
//! host call.
const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const wit_layout = @import("wit_abi_layout.zig");

pub const MemoryOperation = enum {
    read_gc_span,
    flatten_gc_fields,
    validate_linear_range,
    cabi_realloc_alloc,
    copy_to_linear,
    canonical_call,
    copy_from_linear,
    construct_gc_value,
    publish_gc_root,
    cabi_realloc_free,
};

pub const CopyShape = enum {
    scalar,
    text_bytes,
    list_elements,
    record_fields,
};

pub const MemoryPlan = struct {
    direction: marshal.Direction,
    copy_shape: CopyShape,
    element_stride: u32,
    scalar_core_type: ?wit_layout.CoreWord = null,
    element_core_type: ?wit_layout.CoreWord = null,
    result_area_pointer_offset: ?u32 = null,
    result_area_length_offset: ?u32 = null,
    record_field_count: u32 = 0,
    record_indirect: ?wit_layout.IndirectMeasurement = null,
    operations: []const MemoryOperation,
};

pub fn build_sync_memory_plan(plan: *const marshal.SyncValuePlan) !MemoryPlan {
    try marshal.validate_sync_value_plan(plan);
    const measured = plan.root.measured orelse return error.MeasuredLayoutRequired;

    switch (plan.root.kind) {
        .scalar => {
            _ = plan.root.scalar_kind orelse return error.UnsupportedMarshalShape;
            return .{
                .direction = plan.direction,
                .copy_shape = .scalar,
                .element_stride = 0,
                .scalar_core_type = measured.core_type orelse return error.MeasuredScalarCoreTypeMissing,
                .operations = &scalar_operations,
            };
        },
        .text => return .{
            .direction = plan.direction,
            .copy_shape = .text_bytes,
            .element_stride = 1,
            .result_area_pointer_offset = measured.pointer_offset,
            .result_area_length_offset = measured.length_offset,
            .operations = operations_for(plan.direction),
        },
        .list => {
            if (plan.root.children.len != 1) return error.MeasuredChildMissing;
            const child = plan.root.children[0].measured orelse return error.MeasuredChildMissing;
            const stride = measured.element_stride orelse return error.MeasuredElementStrideMissing;
            const element_core_type = if (stride == 1 and child.core_type == null)
                null
            else if (stride == 4 and child.byte_size == 4 and child.alignment == 4 and child.core_type == .i32)
                wit_layout.CoreWord.i32
            else
                return error.UnsupportedMarshalShape;
            return .{
                .direction = plan.direction,
                .copy_shape = .list_elements,
                .element_stride = stride,
                .element_core_type = element_core_type,
                .result_area_pointer_offset = measured.pointer_offset,
                .result_area_length_offset = measured.length_offset,
                .operations = operations_for(plan.direction),
            };
        },
        .record => {
            if (plan.root.children.len == 0 or plan.root.children.len > std.math.maxInt(u32)) {
                return error.UnsupportedMarshalShape;
            }
            for (plan.root.children) |*child| {
                if (child.kind != .scalar) return error.UnsupportedMarshalShape;
                switch (child.scalar_kind orelse return error.UnsupportedMarshalShape) {
                    .u32, .u64, .i64 => {},
                    else => return error.UnsupportedMarshalShape,
                }
                const facts = child.measured orelse return error.MeasuredChildMissing;
                if (facts.core_type == null) return error.MeasuredScalarCoreTypeMissing;
            }
            const record_indirect = plan.root.measured.?.indirect;
            if (record_indirect) |indirect| {
                if (plan.direction != .lower or indirect.core_words.len != 1 or
                    indirect.core_words[0] != .i32 or indirect.allocation != .cabi_realloc or
                    indirect.free != .cabi_realloc)
                {
                    return error.UnsupportedMarshalShape;
                }
            }
            return .{
                .direction = plan.direction,
                .copy_shape = .record_fields,
                .element_stride = 0,
                .record_field_count = @intCast(plan.root.children.len),
                .record_indirect = record_indirect,
                .operations = if (record_indirect != null)
                    &record_indirect_lower_operations
                else if (plan.direction == .lower)
                    &record_lower_operations
                else
                    &record_lift_operations,
            };
        },
    }
}

pub fn validate_linear_span(pointer: u32, length: u32, memory_size: u32) !void {
    if (pointer > memory_size) return error.PointerOutOfBounds;
    if (length > memory_size - pointer) return error.LengthOutOfBounds;
}

pub fn copy_byte_count(length: u32, stride: u32) !u32 {
    if (stride == 0) return error.InvalidCopyStride;
    const total = @as(u64, length) * @as(u64, stride);
    if (total > std.math.maxInt(u32)) return error.CopyByteCountOverflow;
    return @as(u32, @intCast(total));
}

fn operations_for(direction: marshal.Direction) []const MemoryOperation {
    return switch (direction) {
        .lower => &lower_operations,
        .lift => &lift_operations,
    };
}

const lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
};

const lift_operations = [_]MemoryOperation{
    .canonical_call,
    .validate_linear_range,
    .copy_from_linear,
    .construct_gc_value,
    .publish_gc_root,
    .cabi_realloc_free,
};

const scalar_operations = [_]MemoryOperation{
    .canonical_call,
};

const record_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .flatten_gc_fields,
    .canonical_call,
};

const record_indirect_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .flatten_gc_fields,
    .canonical_call,
    .cabi_realloc_free,
};

const record_lift_operations = [_]MemoryOperation{
    .canonical_call,
    .validate_linear_range,
    .copy_from_linear,
    .construct_gc_value,
    .publish_gc_root,
};

test "marshal operation plan preserves lower and lift ordering" {
    try std.testing.expectEqual(MemoryOperation.read_gc_span, lower_operations[0]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_free, lower_operations[5]);
    try std.testing.expectEqual(MemoryOperation.canonical_call, lift_operations[0]);
    try std.testing.expectEqual(MemoryOperation.publish_gc_root, lift_operations[4]);
}

test "marshal operation plan admits measured scalar direct calls" {
    var value = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.scalar",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    }, &value, .lower, .{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.scalar, memory_plan.copy_shape);
    try std.testing.expectEqual(@as(usize, 1), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[0]);
}

test "marshal operation plan admits measured u32 list copies" {
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    }, &value, .lower, .{ .layout = .{ .list = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 4,
        .element_stride = 4,
        .element_alignment = 4,
        .ticket_offset = 0,
        .capacity = 4,
        .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } }, .children = &.{.{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } }} });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.list_elements, memory_plan.copy_shape);
    try std.testing.expectEqual(@as(u32, 4), memory_plan.element_stride);
    try std.testing.expectEqual(@as(usize, 6), memory_plan.operations.len);
}

test "marshal operation plan admits measured scalar record lift" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var count = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer count.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "count", .value = &count },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    }, &value, .lift, .{
        .layout = .{ .record = .{
            .byte_size = 8,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "count", .offset = 4, .byte_size = 4, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expectEqual(@as(u32, 2), memory_plan.record_field_count);
    try std.testing.expectEqual(@as(usize, 5), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[0]);
    try std.testing.expectEqual(MemoryOperation.publish_gc_root, memory_plan.operations[4]);
}

test "marshal operation plan admits measured scalar record lower" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var count = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer count.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "count", .value = &count },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 8,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "count", .offset = 4, .byte_size = 4, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expectEqual(marshal.Direction.lower, memory_plan.direction);
    try std.testing.expectEqual(@as(u32, 2), memory_plan.record_field_count);
    try std.testing.expectEqual(@as(usize, 3), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.read_gc_span, memory_plan.operations[0]);
    try std.testing.expectEqual(MemoryOperation.flatten_gc_fields, memory_plan.operations[1]);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[2]);
}
