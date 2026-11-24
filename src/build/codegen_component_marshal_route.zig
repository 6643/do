const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const marshal_module = @import("codegen_component_marshal_module.zig");
const marshal_registry = @import("codegen_component_marshal_registry.zig");

pub const Request = struct {
    source: []const u8,
    world_name: []const u8,
    interface_name: []const u8,
    member_name: []const u8,
    direction: marshal.Direction,
    measured: marshal.MeasuredNode,
    canonical_u64_arg: ?u64 = null,
    emit_realloc_counters: bool = false,
};

pub fn emit_sync_marshal_module_from_wit_source(
    allocator: std.mem.Allocator,
    request: Request,
) ![]u8 {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        allocator,
        request.source,
        request.world_name,
        request.interface_name,
        request.member_name,
        request.direction,
        request.measured,
    );
    defer marshal.deinit_sync_value_plan(allocator, plan);

    return emit_sync_marshal_module_from_plan(
        allocator,
        &plan,
        request.canonical_u64_arg,
        request.emit_realloc_counters,
    );
}

/// Emit a module from a parser-backed, measured plan. The plan owns the
/// descriptor identity used to derive and validate the canonical Component
/// import; no independent package/member/source facts are accepted here.
pub fn emit_sync_marshal_module_from_plan(
    allocator: std.mem.Allocator,
    plan: *const marshal.SyncValuePlan,
    canonical_u64_arg: ?u64,
    emit_realloc_counters: bool,
) ![]u8 {
    const canonical_import = try marshal_module.canonical_import_for_plan(allocator, plan.descriptor);
    defer allocator.free(canonical_import.module);

    return marshal_module.emit_sync_marshal_module(allocator, plan, .{
        .direction = plan.direction,
        .canonical_import_module = canonical_import.module,
        .canonical_import_name = canonical_import.name,
        .canonical_u64_arg = canonical_u64_arg,
        .emit_realloc_counters = emit_realloc_counters,
    });
}

const source_wit =
    \\package demo:marshal-route@1.0.0;
    \\
    \\interface api {
    \\  read: func() -> u32;
    \\}
    \\
    \\world probe { import api; }
;

const map_source_wit =
    \\package demo:marshal-route-map@1.0.0;
    \\
    \\interface api {
    \\  lookup: func(value: map<u32, u32>) -> map<u32, u32>;
    \\}
    \\
    \\world probe { import api; }
;

test "component marshal route resolves a parser-backed member" {
    const wat = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source_wit,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "read",
        .direction = .lift,
        .measured = .{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .core_type = .i32,
        } } },
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-route/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result i32)") != null);
}

test "component marshal route resolves a parser-backed map member" {
    const measured = marshal.MeasuredNode{
        .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 8,
            .element_stride = 8,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 4, .alignment = 4 },
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    };

    const lower = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = map_source_wit,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "lookup",
        .direction = .lower,
        .measured = measured,
    });
    defer std.testing.allocator.free(lower);
    try std.testing.expect(std.mem.indexOf(u8, lower, "demo:marshal-route-map/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(param $input (ref null $do_map))") != null);

    const lift = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = map_source_wit,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "lookup",
        .direction = .lift,
        .measured = measured,
    });
    defer std.testing.allocator.free(lift);
    try std.testing.expect(std.mem.indexOf(u8, lift, "demo:marshal-route-map/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(result (ref null $do_map))") != null);
}

test "component marshal route resolves a parser-backed scalar list member" {
    const source =
        \\package demo:marshal-route-scalar-list@1.0.0;
        \\
        \\interface api {
        \\  exchange: func(value: list<u16>) -> list<u16>;
        \\}
        \\
        \\world probe { import api; }
    ;
    const measured = marshal.MeasuredNode{
        .layout = .{ .list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 2,
            .element_stride = 2,
            .element_alignment = 2,
            .ticket_offset = 0,
            .capacity = 4,
            .accepted_lengths = &.{ 0, 1, 2, 4 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{.{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 2,
            .alignment = 2,
            .core_type = .i32,
        } } }},
    };
    const lower = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "exchange",
        .direction = .lower,
        .measured = measured,
    });
    defer std.testing.allocator.free(lower);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(type $do_u16 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "i32.store16") != null);

    const lift = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "exchange",
        .direction = .lift,
        .measured = measured,
    });
    defer std.testing.allocator.free(lift);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(result (ref null $do_u16))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift, "i32.load16_u") != null);
}

test "component marshal route resolves parser-backed option and result members" {
    const source =
        \\package demo:marshal-route-variants@1.0.0;
        \\
        \\interface api {
        \\  choose: func(value: option<u32>) -> option<u32>;
        \\  exchange: func(value: result<string, u32>) -> result<string, u32>;
        \\}
        \\
        \\world probe { import api; }
    ;
    const option_measured = marshal.MeasuredNode{
        .layout = .{ .variant = .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{
                .{ .name = "none", .tag = 0, .payload_required = false, .payload = null },
                .{ .name = "some", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        } },
        .children = &.{.{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } }},
    };
    const option = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "choose",
        .direction = .lower,
        .measured = option_measured,
    });
    defer std.testing.allocator.free(option);
    try std.testing.expect(std.mem.indexOf(u8, option, "demo:marshal-route-variants/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, option, "call $canonical_call") != null);

    const result_measured = marshal.MeasuredNode{
        .layout = .{ .variant = .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 12,
            .alignment = 4,
            .cases = &.{
                .{ .name = "ok", .tag = 0, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 8, .alignment = 4, .core_type = .i32 } },
                .{ .name = "err", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        } },
        .children = &.{
            .{ .layout = .{ .text = .{ .pointer_offset = 0, .length_offset = 4, .byte_size = 8, .alignment = 4, .allocation = .cabi_realloc, .free = .cabi_realloc } } },
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    };
    const result = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "exchange",
        .direction = .lift,
        .measured = result_measured,
    });
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "array.new_default $do_u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "call $cabi_realloc") != null);
}

test "component marshal route resolves a parser-backed named variant" {
    const source =
        \\package demo:marshal-route-named-variant@1.0.0;
        \\
        \\interface api {
        \\  variant event { none, value(u32), }
        \\  read: func() -> event;
        \\}
        \\
        \\world probe { import api; }
    ;
    const measured = marshal.MeasuredNode{
        .layout = .{ .variant = .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{
                .{ .name = "none", .tag = 0, .payload_required = false, .payload = null },
                .{ .name = "value", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        } },
        .children = &.{.{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } }},
    };
    const wat = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "read",
        .direction = .lift,
        .measured = measured,
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result i32)") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_variant") != null);
}

test "component marshal route rejects unsupported parser-backed shapes before WAT" {
    const source =
        \\package demo:marshal-route-negative@1.0.0;
        \\
        \\interface api {
        \\  tupled: func(value: tuple<u32, string>) -> u32;
        \\  async_value: func() -> future<u32>;
        \\}
        \\
        \\world probe { import api; }
    ;
    try std.testing.expectError(error.UnsupportedMarshalMember, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "tupled",
        .direction = .lower,
        .measured = .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    }));
    try std.testing.expectError(error.UnsupportedMarshalMember, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "async_value",
        .direction = .lift,
        .measured = .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    }));
}

test "component marshal route admits a scalar tuple lower and lift" {
    const source =
        \\package demo:marshal-route-tuple@1.0.0;
        \\
        \\interface api {
        \\  exchange: func(value: tuple<u32, s64>) -> tuple<u32, s64>;
        \\}
        \\
        \\world probe { import api; }
    ;
    const measured = marshal.MeasuredNode{
        .layout = .{ .tuple = .{
            .byte_size = 16,
            .alignment = 8,
            .fields = &.{
                .{ .offset = 0, .byte_size = 4, .alignment = 4 },
                .{ .offset = 8, .byte_size = 8, .alignment = 8 },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        },
    };
    const lower = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "exchange",
        .direction = .lower,
        .measured = measured,
    });
    defer std.testing.allocator.free(lower);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(type $canonical_lower (func (param i32 i64)))") != null);

    const lift = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "exchange",
        .direction = .lift,
        .measured = measured,
    });
    defer std.testing.allocator.free(lift);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(type $canonical_lift (func (result i32 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(result (ref null $do_tuple))") != null);
}

test "component marshal route lowers a tuple with a scalar byte list child" {
    const source =
        \\package demo:marshal-route-tuple-list@1.0.0;
        \\
        \\interface api { send: func(value: tuple<u32, list<u8>>); }
        \\
        \\world probe { import api; }
    ;
    const wat = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "send",
        .direction = .lower,
        .measured = .{
            .layout = .{ .tuple = .{
                .byte_size = 12,
                .alignment = 4,
                .fields = &.{
                    .{ .offset = 0, .byte_size = 4, .alignment = 4 },
                    .{ .offset = 4, .byte_size = 8, .alignment = 4 },
                },
            } },
            .children = &.{
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .byte_list = .{
                    .pointer_offset = 0,
                    .length_offset = 4,
                    .element_byte_size = 1,
                    .element_stride = 1,
                    .element_alignment = 1,
                    .capacity = 8,
                    .accepted_lengths = &.{ 0, 8 },
                    .allocation = .cabi_realloc,
                    .free = .cabi_realloc,
                } } },
            },
        },
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get_u $do_u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
}

test "component marshal route lifts a tuple with an indirect scalar byte list child" {
    const source =
        \\package demo:marshal-route-tuple-list-lift@1.0.0;
        \\
        \\interface api { receive: func() -> tuple<u32, list<u8>>; }
        \\
        \\world probe { import api; }
    ;
    const wat = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "receive",
        .direction = .lift,
        .measured = .{
            .layout = .{ .tuple = .{
                .byte_size = 12,
                .alignment = 4,
                .fields = &.{
                    .{ .offset = 0, .byte_size = 4, .alignment = 4 },
                    .{ .offset = 4, .byte_size = 8, .alignment = 4 },
                },
                .indirect = .{ .core_words = &.{.i32}, .allocation = .cabi_realloc, .free = .cabi_realloc },
            } },
            .children = &.{
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .byte_list = .{
                    .pointer_offset = 0,
                    .length_offset = 4,
                    .element_byte_size = 1,
                    .element_stride = 1,
                    .element_alignment = 1,
                    .capacity = 8,
                    .accepted_lengths = &.{ 0, 8 },
                    .allocation = .cabi_realloc,
                    .free = .cabi_realloc,
                } } },
            },
        },
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load8_u") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_tuple") != null);
}

test "component marshal route lowers a tuple with two direct list children" {
    const source =
        \\package demo:marshal-route-tuple-two-lists@1.0.0;
        \\
        \\interface api { send: func(value: tuple<u32, list<u8>, list<u32>>); }
        \\
        \\world probe { import api; }
    ;
    const measured = marshal.MeasuredNode{
        .layout = .{ .tuple = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .offset = 0, .byte_size = 4, .alignment = 4 },
                .{ .offset = 4, .byte_size = 8, .alignment = 4 },
                .{ .offset = 12, .byte_size = 8, .alignment = 4 },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .byte_list = .{
                .pointer_offset = 0, .length_offset = 4, .element_byte_size = 1,
                .element_stride = 1, .element_alignment = 1, .capacity = 4,
                .accepted_lengths = &.{ 0, 4 }, .allocation = .cabi_realloc, .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0, .length_offset = 4, .element_byte_size = 4,
                .element_stride = 4, .element_alignment = 4, .ticket_offset = 0, .capacity = 3,
                .accepted_lengths = &.{ 0, 3 }, .allocation = .cabi_realloc, .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32,
            } } }} },
        },
    };
    const wat = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "send",
        .direction = .lower,
        .measured = measured,
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__tuple_list_array_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__tuple_list_array_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__tuple_list_pointer_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__tuple_list_pointer_1") != null);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, wat, "call $cabi_realloc"));
}

test "component marshal route lowers a tuple with a nested list child" {
    const source =
        \\package demo:marshal-route-tuple-nested-list@1.0.0;
        \\
        \\interface api { send: func(value: tuple<u32, tuple<list<u8>, u32>>); }
        \\
        \\world probe { import api; }
    ;
    const wat = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "send",
        .direction = .lower,
        .measured = .{
            .layout = .{ .tuple = .{
                .byte_size = 16,
                .alignment = 4,
                .fields = &.{
                    .{ .offset = 0, .byte_size = 4, .alignment = 4 },
                    .{ .offset = 4, .byte_size = 12, .alignment = 4 },
                },
            } },
            .children = &.{
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .tuple = .{
                    .byte_size = 12,
                    .alignment = 4,
                    .fields = &.{
                        .{ .offset = 0, .byte_size = 8, .alignment = 4 },
                        .{ .offset = 8, .byte_size = 4, .alignment = 4 },
                    },
                } }, .children = &.{
                    .{ .layout = .{ .byte_list = .{
                        .pointer_offset = 0, .length_offset = 4, .element_byte_size = 1,
                        .element_stride = 1, .element_alignment = 1, .capacity = 4,
                        .accepted_lengths = &.{ 0, 4 }, .allocation = .cabi_realloc, .free = .cabi_realloc,
                    } } },
                    .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                } },
            },
        },
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_tuple_1 $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_tuple_1 $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__tuple_list_array_0") != null);
}

test "component marshal route resolves a parser-backed list of scalar tuples" {
    const source =
        \\package demo:marshal-route-list-tuple@1.0.0;
        \\
        \\interface api {
        \\  exchange: func(value: list<tuple<u32, s64>>) -> list<tuple<u32, s64>>;
        \\
        \\world probe { import api; }
    ;
    const measured = marshal.MeasuredNode{
        .layout = .{ .list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 16,
            .element_stride = 16,
            .element_alignment = 8,
            .ticket_offset = 0,
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{.{
            .layout = .{ .tuple = .{
                .byte_size = 16,
                .alignment = 8,
                .fields = &.{
                    .{ .offset = 0, .byte_size = 4, .alignment = 4 },
                    .{ .offset = 8, .byte_size = 8, .alignment = 8 },
                },
            } },
            .children = &.{
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            },
        }},
    };

    const lower = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "exchange",
        .direction = .lower,
        .measured = measured,
    });
    defer std.testing.allocator.free(lower);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "(type $do_list_tuple_element (struct (field $field0 i32) (field $field1 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower, "i64.store") != null);

    const lift = try emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "exchange",
        .direction = .lift,
        .measured = measured,
    });
    defer std.testing.allocator.free(lift);
    try std.testing.expect(std.mem.indexOf(u8, lift, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift, "struct.new $do_list_tuple_element") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift, "i64.load") != null);
}

test "component marshal route rejects unsupported list tuple shapes before WAT" {
    const source =
        \\package demo:marshal-route-list-tuple-negative@1.0.0;
        \\
        \\interface api {
        \\  text_value: func(value: list<tuple<string, u32>>);
        \\  nested_list: func(value: list<tuple<list<u32>, u32>>);
        \\  stride_value: func(value: list<tuple<u32, s64>>);
        \\
        \\world probe { import api; }
    ;
    const scalar_measured = marshal.MeasuredNode{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } };
    try std.testing.expectError(error.UnsupportedWitMarshalShape, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "text_value",
        .direction = .lower,
        .measured = scalar_measured,
    }));

    const nested_list_measured = marshal.MeasuredNode{
        .layout = .{ .list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 12,
            .element_stride = 12,
            .element_alignment = 4,
            .ticket_offset = 0,
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{.{
            .layout = .{ .tuple = .{
                .byte_size = 12,
                .alignment = 4,
                .fields = &.{
                    .{ .offset = 0, .byte_size = 8, .alignment = 4 },
                    .{ .offset = 8, .byte_size = 4, .alignment = 4 },
                },
            } },
            .children = &.{
                .{ .layout = .{ .list = .{
                    .pointer_offset = 0,
                    .length_offset = 4,
                    .element_byte_size = 4,
                    .element_stride = 4,
                    .element_alignment = 4,
                    .ticket_offset = 0,
                    .capacity = 2,
                    .accepted_lengths = &.{ 0, 1, 2 },
                    .allocation = .cabi_realloc,
                    .free = .cabi_realloc,
                } },
                .children = &.{.{ .layout = .{ .scalar = .{
                    .offset = 0,
                    .byte_size = 4,
                    .alignment = 4,
                    .core_type = .i32,
                } } }},
                },
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            },
        }},
    };
    try std.testing.expectError(error.UnsupportedMarshalShape, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "nested_list",
        .direction = .lower,
        .measured = nested_list_measured,
    }));

    const stride_measured = marshal.MeasuredNode{
        .layout = .{ .list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 16,
            .element_stride = 24,
            .element_alignment = 8,
            .ticket_offset = 0,
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{.{
            .layout = .{ .tuple = .{
                .byte_size = 16,
                .alignment = 8,
                .fields = &.{
                    .{ .offset = 0, .byte_size = 4, .alignment = 4 },
                    .{ .offset = 8, .byte_size = 8, .alignment = 8 },
                },
            } },
            .children = &.{
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            },
        }},
    };
    try std.testing.expectError(error.UnsupportedMarshalShape, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "stride_value",
        .direction = .lower,
        .measured = stride_measured,
    }));
}

test "component marshal route rejects resource and async variant payloads before WAT" {
    const source =
        \\package demo:marshal-route-unsupported-variants@1.0.0;
        \\
        \\interface api {
        \\  variant resource_event { opened(handle), }
        \\  resource handle {}
        \\  resource_value: func() -> resource_event;
        \\  async_value: func() -> result<future<u32>, u32>;
        \\}
        \\
        \\world probe { import api; }
    ;
    const scalar_measured = marshal.MeasuredNode{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } };

    try std.testing.expectError(error.UnsupportedMarshalMember, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "resource_value",
        .direction = .lift,
        .measured = scalar_measured,
    }));
    try std.testing.expectError(error.UnsupportedMarshalMember, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "async_value",
        .direction = .lift,
        .measured = scalar_measured,
    }));
}

test "component marshal route rejects variant measurement case drift before WAT" {
    const source =
        \\package demo:marshal-route-variant-drift@1.0.0;
        \\
        \\interface api {
        \\  choose: func() -> option<u32>;
        \\}
        \\
        \\world probe { import api; }
    ;
    const drifted = marshal.MeasuredNode{
        .layout = .{ .variant = .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{
                .{ .name = "none", .tag = 0, .payload_required = false, .payload = null },
                .{ .name = "renamed", .tag = 1, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        } },
        .children = &.{.{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } }},
    };
    try std.testing.expectError(error.MissingPayloadMetadata, emit_sync_marshal_module_from_wit_source(std.testing.allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = "choose",
        .direction = .lift,
        .measured = drifted,
    }));
}
