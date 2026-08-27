const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const descriptor_loader = @import("codegen_component_descriptor_manifest.zig");
const manifest_route = @import("codegen_component_manifest_route.zig");
const wit_layout = @import("wit_abi_layout.zig");

const manifest_path = "doc/wit/gc_descriptor_manifest.json";
const random_descriptor = "wasi:random/random.get-random-bytes@0.3.0-rc-2025-09-16/lift";
const text_descriptor = "demo:marshal-equivalence/api.send@1.0.0/lower";
const u32_list_descriptor = "demo:marshal-u32-equivalence/api.send@1.0.0/lower";
const u32_list_lift_descriptor = "demo:marshal-u32-lift-host/api.receive@1.0.0/lift";
const record_lower_descriptor = "demo:marshal-record-lower/api.write@1.0.0/lower";
const record_lift_descriptor = "demo:marshal-record-host/api.read@1.0.0/lift";
const mixed_record_lift_descriptor = "demo:marshal-record-mixed-host/api.read@1.0.0/lift";
const indirect_record_lower_descriptor = "demo:marshal-record-indirect-lower/api.write@1.0.0/lower";
const nested_record_lift_descriptor = "demo:marshal-record-nested-host/api.read@1.0.0/lift";
const nested_record_lower_descriptor = "demo:marshal-record-nested-lower/api.write@1.0.0/lower";
const nested_record_lower_deep_descriptor = "demo:marshal-record-nested-lower-deep/api.write@1.0.0/lower";
const nested_record_lift_deep_descriptor = "demo:marshal-record-nested-lift-deep/api.read@1.0.0/lift";
const nested_record_lower_deeper_descriptor = "demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower";
const nested_record_lift_deeper_descriptor = "demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift";
const managed_record_lift_descriptor = "demo:marshal-record-managed-lift/api.read@1.0.0/lift";
const managed_record_lower_descriptor = "demo:marshal-record-managed-lower/api.write@1.0.0/lower";
const managed_record_lower_multi_descriptor = "demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower";
const u32_list_record_lower_descriptor = "demo:marshal-record-u32-list-lower/api.write@1.0.0/lower";
const mixed_text_u32_list_record_lower_descriptor = "demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower";
const mixed_text_byte_list_lift_descriptor = "demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift";

test "manifest route emits from one loaded request" {
    var loaded = try descriptor_loader.load_request_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        mixed_text_byte_list_lift_descriptor,
        null,
    );
    defer loaded.deinit();
    const wat = try manifest_route.emit_sync_marshal_module_from_loaded_request(
        std.testing.allocator,
        &loaded,
        null,
        true,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import") != null);
}

fn random_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .byte_list = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 1,
        .element_stride = 1,
        .element_alignment = 1,
        .capacity = 16,
        .accepted_lengths = &.{ 0, 1, 16 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } };
}

fn text_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .text = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } };
}

fn u32_list_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .list = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 4,
        .element_stride = 4,
        .element_alignment = 4,
        .ticket_offset = 0,
        .capacity = 3,
        .accepted_lengths = &.{ 0, 1, 2, 3 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } }, .children = &.{.{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } }} };
}

fn u32_list_record_lower_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 12,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "payload", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 4,
            .element_stride = 4,
            .element_alignment = 4,
            .ticket_offset = 0,
            .capacity = 3,
            .accepted_lengths = &.{ 0, 1, 2, 3 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } }, .children = &.{.{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .core_type = .i32,
        } } }} },
    } };
}

fn mixed_text_u32_list_record_lower_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 20,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
            .{ .name = "payload", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
        .{ .layout = .{ .list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 4,
            .element_stride = 4,
            .element_alignment = 4,
            .ticket_offset = 0,
            .capacity = 3,
            .accepted_lengths = &.{ 0, 1, 2, 3 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } }, .children = &.{.{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .core_type = .i32,
        } } }} },
    } };
}

fn mixed_text_byte_list_lift_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 20,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
            .{ .name = "payload", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
        .{ .layout = .{ .byte_list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 1,
            .element_stride = 1,
            .element_alignment = 1,
            .capacity = 4,
            .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
    } };
}

fn record_lower_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 8,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "count", .offset = 4, .byte_size = 4, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    } };
}

fn record_lift_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 8,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "count", .offset = 4, .byte_size = 4, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    } };
}

fn mixed_record_lift_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 24,
        .alignment = 8,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
            .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
    } };
}

fn nested_record_lift_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 32,
        .alignment = 8,
        .fields = &.{
            .{ .name = "header", .offset = 0, .byte_size = 16, .alignment = 8, .indirect = null },
            .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .record = .{
            .byte_size = 16,
            .alignment = 8,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } }, .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        } },
        .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
    } };
}

fn nested_record_lower_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 32,
        .alignment = 8,
        .fields = &.{
            .{ .name = "header", .offset = 0, .byte_size = 16, .alignment = 8, .indirect = null },
            .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .record = .{
            .byte_size = 16,
            .alignment = 8,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } }, .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        } },
        .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
    } };
}

fn nested_record_lower_deep_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 48,
        .alignment = 8,
        .fields = &.{
            .{ .name = "detail", .offset = 0, .byte_size = 32, .alignment = 8, .indirect = null },
            .{ .name = "tail", .offset = 32, .byte_size = 8, .alignment = 8, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .record = .{
            .byte_size = 32,
            .alignment = 8,
            .fields = &.{
                .{ .name = "header", .offset = 0, .byte_size = 16, .alignment = 8, .indirect = null },
                .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } }, .children = &.{
            .{ .layout = .{ .record = .{
                .byte_size = 16,
                .alignment = 8,
                .fields = &.{
                    .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                    .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
                },
            } }, .children = &.{
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            } },
            .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        } },
        .{ .layout = .{ .scalar = .{ .offset = 32, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
    } };
}

fn nested_record_lift_deep_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 32,
        .alignment = 8,
        .fields = &.{
            .{ .name = "detail", .offset = 0, .byte_size = 24, .alignment = 8, .indirect = null },
            .{ .name = "tail", .offset = 24, .byte_size = 8, .alignment = 8, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .record = .{
            .byte_size = 24,
            .alignment = 8,
            .fields = &.{
                .{ .name = "header", .offset = 0, .byte_size = 16, .alignment = 8, .indirect = null },
                .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } }, .children = &.{
            .{ .layout = .{ .record = .{
                .byte_size = 16,
                .alignment = 8,
                .fields = &.{
                    .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                    .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
                },
            } }, .children = &. {
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            } },
            .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        } },
        .{ .layout = .{ .scalar = .{ .offset = 24, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
    } };
}

fn nested_record_lower_deeper_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 40,
        .alignment = 8,
        .fields = &.{
            .{ .name = "detail", .offset = 0, .byte_size = 32, .alignment = 8, .indirect = null },
            .{ .name = "tail", .offset = 32, .byte_size = 8, .alignment = 8, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .record = .{
            .byte_size = 32,
            .alignment = 8,
            .fields = &.{
                .{ .name = "header", .offset = 0, .byte_size = 24, .alignment = 8, .indirect = null },
                .{ .name = "marker", .offset = 24, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } }, .children = &.{
            .{ .layout = .{ .record = .{
                .byte_size = 24,
                .alignment = 8,
                .fields = &.{
                    .{ .name = "leaf", .offset = 0, .byte_size = 16, .alignment = 8, .indirect = null },
                    .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
                },
            } }, .children = &.{
                .{ .layout = .{ .record = .{
                    .byte_size = 16,
                    .alignment = 8,
                    .fields = &.{
                        .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                        .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
                    },
                } }, .children = &.{
                    .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                    .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
                } },
                .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            } },
            .{ .layout = .{ .scalar = .{ .offset = 24, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        } },
        .{ .layout = .{ .scalar = .{ .offset = 32, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
    } };
}

fn nested_record_lift_deeper_measurement() marshal.MeasuredNode {
    return nested_record_lower_deeper_measurement();
}

fn managed_record_lift_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 12,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
    } };
}

fn managed_record_lower_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 12,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
    } };
}

fn managed_record_lower_multi_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 20,
        .alignment = 4,
        .fields = &.{
            .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
            .{ .name = "note", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
        },
    } }, .children = &.{
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
    } };
}

fn make_indirect_record_fields() [17]wit_layout.FieldMeasurement {
    var fields: [17]wit_layout.FieldMeasurement = undefined;
    inline for (0..17) |index| {
        fields[index] = .{
            .name = comptime std.fmt.comptimePrint("f{d}", .{index}),
            .offset = @intCast(index * 8),
            .byte_size = 8,
            .alignment = 8,
            .indirect = null,
        };
    }
    return fields;
}

fn make_indirect_record_children() [17]marshal.MeasuredNode {
    var children: [17]marshal.MeasuredNode = undefined;
    inline for (0..17) |index| {
        children[index] = .{ .layout = .{ .scalar = .{
            .offset = @intCast(index * 8),
            .byte_size = 8,
            .alignment = 8,
            .core_type = .i64,
        } } };
    }
    return children;
}

const indirect_record_fields = make_indirect_record_fields();
const indirect_record_children = make_indirect_record_children();

fn indirect_record_lower_measurement() marshal.MeasuredNode {
    return .{ .layout = .{ .record = .{
        .byte_size = 136,
        .alignment = 8,
        .fields = &indirect_record_fields,
        .indirect = .{
            .core_words = &.{.i32},
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        },
    } }, .children = &indirect_record_children };
}

test "manifest route emits the pinned random GC lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        random_descriptor,
        random_measurement(),
        16,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "wasi:random/random@0.3.0-rc-2025-09-16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i64 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"wasi:random/random@0.3.0-rc-2025-09-16\" \"get-random-bytes\" (func $canonical_call (param (ref") == null);
}

test "manifest route rejects an unknown descriptor before emission" {
    try std.testing.expectError(error.DescriptorNotFound, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        "wasi:random/random.missing@0.3.0-rc-2025-09-16/lift",
        random_measurement(),
        16,
    ));
}

test "manifest route emits the pinned text lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        text_descriptor,
        text_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-equivalence/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-equivalence/api@1.0.0\" \"send\"") != null);
}

test "manifest route emits the pinned u32 list lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        u32_list_descriptor,
        u32_list_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-u32-equivalence/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
}

test "manifest route emits the pinned u32 list lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        u32_list_lift_descriptor,
        u32_list_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-u32-lift-host/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
}

test "manifest route emits the pinned scalar record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        record_lower_descriptor,
        record_lower_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
}

test "manifest route emits the pinned u32-list record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        u32_list_record_lower_descriptor,
        u32_list_record_lower_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-u32-list-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
}

test "manifest route emits the pinned mixed text u32-list record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        mixed_text_u32_list_record_lower_descriptor,
        mixed_text_u32_list_record_lower_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.store\n") != null);
}

test "manifest route emits the pinned mixed text byte-list record lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        mixed_text_byte_list_lift_descriptor,
        mixed_text_byte_list_lift_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_bytes)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load8_u") != null);
}

test "manifest-owned route emits the pinned u32-list record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest_owned(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        u32_list_record_lower_descriptor,
        null,
        false,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-u32-list-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
}

test "manifest route emits the pinned scalar record lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        record_lift_descriptor,
        record_lift_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-host/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0\n    i32.add\n    i32.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 4\n    i32.add\n    i32.load") != null);
}

test "manifest route emits the pinned mixed scalar record lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        mixed_record_lift_descriptor,
        mixed_record_lift_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-mixed-host/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0\n    i32.add\n    i32.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 8\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 16\n    i32.add\n    i64.load") != null);
}

test "manifest route emits the pinned nested scalar record lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lift_descriptor,
        nested_record_lift_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-host/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 8\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 16\n    i32.add\n    i64.load") != null);
}

test "manifest route emits the pinned nested scalar record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lower_descriptor,
        nested_record_lower_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i64 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_header $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_header $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-nested-lower/api@1.0.0\" \"write\" (func $canonical_call (param (ref)") == null);
}

test "manifest route emits the pinned three-level nested scalar record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lower_deep_descriptor,
        nested_record_lower_deep_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lower-deep/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i64 i64 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_detail $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_header $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
}

test "manifest route emits the pinned three-level nested scalar record lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lift_deep_descriptor,
        nested_record_lift_deep_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lift-deep/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 8\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 16\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 24\n    i32.add\n    i64.load") != null);
}

test "manifest route emits the pinned four-level nested scalar record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lower_deeper_descriptor,
        nested_record_lower_deeper_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lower-deeper/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i64 i64 i64 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_leaf $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_header $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_detail $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-nested-lower-deeper/api@1.0.0\" \"write\" (func $canonical_call (param (ref)") == null);
}

test "manifest route emits the pinned four-level nested scalar record lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lift_deeper_descriptor,
        nested_record_lift_deeper_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-nested-lift-deeper/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_header") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_detail") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 8\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 16\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 24\n    i32.add\n    i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 32\n    i32.add\n    i64.load") != null);
}

test "manifest route emits the pinned managed-field record lift" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        managed_record_lift_descriptor,
        managed_record_lift_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $field1 (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
}

test "manifest route emits a managed record from manifest-owned measurement" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest_owned(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        managed_record_lift_descriptor,
        null,
        false,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lift/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $field1 (ref null $do_text))") != null);
}

test "manifest route rejects managed-field record lift child-count drift" {
    var measurement = managed_record_lift_measurement();
    measurement.children = &.{measurement.children[0]};
    try std.testing.expectError(error.MeasuredChildCountMismatch, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        managed_record_lift_descriptor,
        measurement,
        null,
    ));
}

test "manifest route emits the pinned managed-field record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        managed_record_lower_descriptor,
        managed_record_lower_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get_s $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
}

test "manifest route admits the pinned multi-managed-text record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        managed_record_lower_multi_descriptor,
        managed_record_lower_multi_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lower-multi/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32)))") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
}

test "manifest route rejects managed-field record lower child-count drift" {
    var measurement = managed_record_lower_measurement();
    measurement.children = &.{measurement.children[0]};
    try std.testing.expectError(error.MeasuredChildCountMismatch, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        managed_record_lower_descriptor,
        measurement,
        null,
    ));
}

test "manifest route rejects three-level nested scalar record lift child-count drift" {
    var measurement = nested_record_lift_deep_measurement();
    measurement.children = &.{measurement.children[0]};
    try std.testing.expectError(error.MeasuredChildCountMismatch, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lift_deep_descriptor,
        measurement,
        null,
    ));
}

test "manifest route rejects three-level nested scalar record child-count drift" {
    var measurement = nested_record_lower_deep_measurement();
    measurement.children = &.{measurement.children[0]};
    try std.testing.expectError(error.MeasuredChildCountMismatch, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lower_deep_descriptor,
        measurement,
        null,
    ));
}

test "manifest route rejects nested scalar record lower child-count drift" {
    var measurement = nested_record_lower_measurement();
    measurement.children = &.{measurement.children[0]};
    try std.testing.expectError(error.MeasuredChildCountMismatch, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lower_descriptor,
        measurement,
        null,
    ));
}

test "manifest route rejects nested scalar record measurement depth drift" {
    var measurement = nested_record_lift_measurement();
    measurement.children = &.{
        measurement.children[0],
        measurement.children[1],
        .{ .layout = .{ .scalar = .{ .offset = 24, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    };
    try std.testing.expectError(error.MeasuredChildCountMismatch, manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        nested_record_lift_descriptor,
        measurement,
        null,
    ));
}

test "manifest route emits the pinned indirect scalar record lower" {
    const wat = try manifest_route.emit_sync_marshal_module_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        manifest_path,
        indirect_record_lower_descriptor,
        indirect_record_lower_measurement(),
        null,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-indirect-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store offset=128") != null);
}
