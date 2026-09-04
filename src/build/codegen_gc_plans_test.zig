const std = @import("std");
const representation = @import("codegen_gc_representation.zig");
const roots = @import("codegen_gc_roots.zig");
const abi = @import("codegen_component_abi_plan.zig");
const resources = @import("codegen_component_resource_plan.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const marshal_ops = @import("codegen_component_marshal_ops.zig");
const marshal_module = @import("codegen_component_marshal_module.zig");
const marshal_wat = @import("codegen_component_marshal_wat.zig");
const marshal_registry = @import("codegen_component_marshal_registry.zig");
const descriptor_loader = @import("codegen_component_descriptor_manifest.zig");
const marshal_route = @import("codegen_component_marshal_route.zig");
const wit_types = @import("wit_abi_types.zig");
const wit_layout = @import("wit_abi_layout.zig");
const wit_resolve = @import("../wit/resolve.zig");
const wit_registry = @import("../wit/marshal_registry.zig");
const lexer = @import("lexer.zig");

const bounded_text_marshal_wit =
    \\package demo:marshal@1.0.0;
    \\
    \\interface api {
    \\  send: func(value: string);
    \\}
    \\
    \\world probe { import api; }
;

const unsupported_map_marshal_wit =
    \\package demo:marshal-map@1.0.0;
    \\
    \\interface api {
    \\  lookup: func(value: map<string, u32>) -> map<u32, string>;
    \\}
    \\
    \\world probe { import api; }
;

test "WIT registry adapter converts map key and value types" {
    var binding = try wit_resolve.resolve_source(std.testing.allocator, unsupported_map_marshal_wit, "probe");
    defer binding.deinit();
    const member = try wit_registry.find_value_member(&binding, "api", "lookup");

    var lower = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &member, .lower);
    defer lower.deinit();
    try std.testing.expectEqual(wit_types.AbiTypeKind.map, lower.kind());
    try std.testing.expectEqual(wit_types.AbiTypeKind.text, lower.map_key().?.kind());
    try std.testing.expectEqual(wit_types.ScalarKind.u32, lower.map_value().?.scalar_kind().?);

    var lift = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &member, .lift);
    defer lift.deinit();
    try std.testing.expectEqual(wit_types.AbiTypeKind.map, lift.kind());
    try std.testing.expectEqual(wit_types.ScalarKind.u32, lift.map_key().?.scalar_kind().?);
    try std.testing.expectEqual(wit_types.AbiTypeKind.text, lift.map_value().?.kind());
}

const bounded_scalar_record_marshal_wit =
    \\package demo:marshal-record@1.0.0;
    \\
    \\interface api {
    \\  record reading {
    \\    code: u32,
    \\    count: u32,
    \\  }
    \\
    \\  read: func() -> reading;
    \\}
    \\
    \\world probe { import api; }
;

test "marshal module wrapper emits bounded lower text module" {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        std.testing.allocator,
        bounded_text_marshal_wit,
        "probe",
        "api",
        "send",
        .lower,
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
    );
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const module_wat = try marshal_module.emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .function_name = "marshal",
        .export_name = "marshal",
        .canonical_import_module = "demo:marshal/api@1.0.0",
        .canonical_import_name = "send",
    });
    defer std.testing.allocator.free(module_wat);

    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(type $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(memory (export \"memory\") 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(type $cabi_realloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(import \"demo:marshal/api@1.0.0\" \"send\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(export \"marshal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(import \"demo:marshal/api@1.0.0\" \"send\" (func $canonical_call (type $canonical_lower)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(import \"demo:marshal/api@1.0.0\" \"send\" (func $canonical_call (param") == null);
}

test "parser-backed scalar record lift emits a GC record module" {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        std.testing.allocator,
        bounded_scalar_record_marshal_wit,
        "probe",
        "api",
        "read",
        .lift,
        .{
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
        },
    );
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(marshal.Direction.lift, plan.direction);
    try std.testing.expectEqual(marshal.NodeKind.record, plan.root.kind);
    try std.testing.expectEqual(@as(u32, 8), plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(usize, 0), plan.abi.arguments.len);
    try std.testing.expectEqual(@as(usize, 1), plan.abi.results.len);
    try std.testing.expectEqualStrings("memory", plan.abi.results[0].canonical_type);
    try std.testing.expect(!plan.contains_gc_reference);

    const module_wat = try marshal_module.emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lift,
        .canonical_import_module = "demo:marshal-record/api@1.0.0",
        .canonical_import_name = "read",
    });
    defer std.testing.allocator.free(module_wat);

    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(type $do_record (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "cabi_realloc") == null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(import \"demo:marshal-record/api@1.0.0\" \"read\" (func $canonical_call (type $canonical_lift)))") != null);
}

test "GC root plan excludes inline values and rejects resources" {
    const locals = [_]roots.RootLocal{
        .{ .name = "count", .rep = .inline_value },
        .{ .name = "message", .rep = .gc_managed },
    };
    const plan = try roots.build_root_plan(std.testing.allocator, locals[0..], .synchronous);
    defer roots.deinit_root_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(@as(usize, 1), plan.slots.len);
    try std.testing.expectEqualStrings("message", plan.slots[0].name);
    try std.testing.expectEqual(roots.RootPoint.local_bind, plan.slots[0].point);

    const resource_locals = [_]roots.RootLocal{
        .{ .name = "file", .rep = .resource_handle },
    };
    try std.testing.expectError(error.ResourceCannotBeGcRoot, roots.build_root_plan(std.testing.allocator, resource_locals[0..], .synchronous));
}

test "synchronous GC root plan rejects duplicate managed locals" {
    const locals = [_]roots.RootLocal{
        .{ .name = "message", .rep = .gc_managed },
        .{ .name = "message", .rep = .gc_managed },
    };
    try std.testing.expectError(
        error.DuplicateRootLocal,
        roots.build_root_plan(std.testing.allocator, locals[0..], .synchronous),
    );
}

test "ABI plan rejects GC references at canonical boundary" {
    const illegal = abi.AbiPlan{
        .package = "pkg",
        .world = "world",
        .member = "call",
        .arguments = &.{.{ .source_type = "text", .canonical_type = "(ref null $do_text)", .direction = .lower, .contains_gc_reference = true }},
        .results = &.{},
    };
    try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, abi.validate_abi_plan(illegal));
}

test "resource plan requires exactly one terminal action" {
    const transfers = [_]resources.ResourceTransfer{
        .{ .type_name = "File", .direction = .own_in, .drop_authority = true },
    };
    const duplicate = resources.ResourceFacts{
        .transfers = transfers[0..],
        .terminal_actions = &.{ .drop_owned, .drop_owned },
    };
    try std.testing.expectError(error.DuplicateTerminalCleanup, resources.build_resource_plan(std.testing.allocator, duplicate));
}

test "resource plan preserves a single terminal action" {
    const facts = resources.ResourceFacts{
        .transfers = &.{},
        .terminal_actions = &.{.no_resource},
    };
    const plan = try resources.build_resource_plan(std.testing.allocator, facts);
    defer resources.deinit_resource_plan(std.testing.allocator, plan);
    try std.testing.expectEqual(resources.TerminalAction.no_resource, plan.terminal_action);
}

test "representation type remains shared by the three plans" {
    try std.testing.expectEqual(representation.ValueRep.gc_managed, try representation.classify_type("text", &.{}, &.{}));
}

test "suspendable root plan keeps managed frame fields live through terminal" {
    const locals = [_]roots.RootLocal{
        .{ .name = "message", .rep = .gc_managed },
        .{ .name = "count", .rep = .inline_value },
    };
    const plan = try roots.build_suspendable_root_plan(std.testing.allocator, locals[0..]);
    defer roots.deinit_suspendable_root_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(@as(usize, 1), plan.fields.len);
    try std.testing.expectEqualStrings("message", plan.fields[0].name);
    try std.testing.expectEqual(@as(u32, 0), plan.fields[0].field_index);
    try std.testing.expectEqual(roots.RootPoint.terminal, plan.fields[0].live_until);
}

test "resource terminal completion and cancellation race is single shot" {
    const plan_facts = resources.ResourceFacts{
        .transfers = &.{.{ .type_name = "File", .direction = .own_in, .drop_authority = true }},
        .terminal_actions = &.{.drop_owned},
    };
    var plan = try resources.build_resource_plan(std.testing.allocator, plan_facts);
    defer resources.deinit_resource_plan(std.testing.allocator, plan);

    try resources.claim_terminal(&plan, .completed);
    try std.testing.expectError(error.TerminalAlreadyDecided, resources.claim_terminal(&plan, .cancelled));
}

test "resource plan rejects duplicate drop authority for one resource" {
    const transfers = [_]resources.ResourceTransfer{
        .{ .type_name = "File", .direction = .own_in, .drop_authority = true },
        .{ .type_name = "File", .direction = .own_out, .drop_authority = true },
    };
    try std.testing.expectError(
        error.DuplicateResourceDropAuthority,
        resources.build_resource_plan(std.testing.allocator, .{
            .transfers = transfers[0..],
            .terminal_actions = &.{.drop_owned},
        }),
    );
}

test "ABI plan rejects an unmarked GC reference spelling" {
    const illegal = abi.AbiPlan{
        .package = "pkg",
        .world = "world",
        .member = "call",
        .arguments = &.{.{ .source_type = "text", .canonical_type = "(ref null $do_text)", .direction = .lower }},
        .results = &.{},
    };
    try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, abi.validate_abi_plan(illegal));
}

test "canonical marshal plan lowers text to ptr len without a GC reference" {
    var text = wit_types.AbiType.text(std.testing.allocator);
    defer text.deinit();

    const plan = try marshal.build_sync_value_plan(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-text-v1",
    }, &text, .lower);
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(marshal.NodeKind.text, plan.root.kind);
    try std.testing.expectEqual(marshal.CanonicalShape.ptr_len, plan.root.canonical_shape);
    try std.testing.expectEqual(@as(usize, 0), plan.root.children.len);
    try std.testing.expect(!plan.contains_gc_reference);
    try std.testing.expectEqual(@as(usize, 1), plan.abi.arguments.len);
    try std.testing.expectEqualStrings("(i32,i32)", plan.abi.arguments[0].canonical_type);
    try std.testing.expect(!plan.abi.arguments[0].contains_gc_reference);
}

test "canonical marshal plan preserves nested record list children and offsets" {
    var scalar = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer scalar.deinit();
    var text = wit_types.AbiType.text(std.testing.allocator);
    defer text.deinit();
    var text_list = try wit_types.AbiType.list(std.testing.allocator, &text);
    defer text_list.deinit();
    var record = try wit_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "count", .value = &scalar },
        .{ .name = "items", .value = &text_list },
    });
    defer record.deinit();

    const plan = try marshal.build_sync_value_plan(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "batch",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:batch-v1",
    }, &record, .lower);
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(marshal.NodeKind.record, plan.root.kind);
    try std.testing.expectEqual(@as(usize, 2), plan.root.children.len);
    try std.testing.expectEqual(@as(u32, 0), plan.root.children[0].provisional_offset);
    try std.testing.expectEqual(@as(u32, 4), plan.root.children[1].provisional_offset);
    try std.testing.expectEqual(marshal.NodeKind.list, plan.root.children[1].kind);
    try std.testing.expectEqual(@as(usize, 1), plan.root.children[1].children.len);
    try std.testing.expectEqual(marshal.NodeKind.text, plan.root.children[1].children[0].kind);
}

test "canonical marshal plan rejects resource-containing shapes at the resource boundary" {
    var resource = try wit_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer resource.deinit();
    var record = try wit_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "ticket", .value = &resource },
    });
    defer record.deinit();

    try std.testing.expectError(
        error.ResourceBoundaryUnsupported,
        marshal.build_sync_value_plan(std.testing.allocator, .{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "use-ticket",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "sha256:resource-v1",
        }, &record, .lower),
    );
}

test "canonical marshal plan rejects unmeasured managed list element layouts" {
    var text = wit_types.AbiType.text(std.testing.allocator);
    defer text.deinit();
    var record = try wit_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "value", .value = &text },
    });
    defer record.deinit();
    var records = try wit_types.AbiType.list(std.testing.allocator, &record);
    defer records.deinit();

    try std.testing.expectError(
        error.UnsupportedMarshalShape,
        marshal.build_sync_value_plan(std.testing.allocator, .{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "records",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "sha256:records-v1",
        }, &records, .lower),
    );
}

test "canonical marshal plan rejects an invalid descriptor identity" {
    var text = wit_types.AbiType.text(std.testing.allocator);
    defer text.deinit();

    try std.testing.expectError(
        error.InvalidDescriptorIdentity,
        marshal.build_sync_value_plan(std.testing.allocator, .{
            .package = "",
            .world = "host",
            .member = "send",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "",
        }, &text, .lower),
    );
}

const bounded_wit_registry_source =
    \\package demo:marshal@1.0.0;
    \\
    \\interface api {
    \\  record payload { count: u32, data: string, bytes: list<u8>, }
    \\  record node { next: node, }
    \\  variant event { done, }
    \\  scalar_value: func(value: u32);
    \\  transform_value: func(value: u32) -> string;
    \\  too_many_values: func(first: u32, second: u32);
    \\  text_value: func(value: string);
    \\  bytes_value: func(value: list<u8>);
    \\  record_value: func(value: payload);
    \\  unresolved_value: func(value: missing);
    \\  cyclic_value: func(value: node);
    \\  variant_value: func(value: event);
    \\}
    \\
    \\world probe { import api; }
;

test "WIT registry adapter converts bounded scalar value" {
    var binding = try wit_resolve.resolve_source(std.testing.allocator, bounded_wit_registry_source, "probe");
    defer binding.deinit();
    const member = try wit_registry.find_value_member(&binding, "api", "scalar_value");
    var value = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &member, .lower);
    defer value.deinit();

    try std.testing.expectEqual(wit_types.AbiTypeKind.scalar, value.kind());
    try std.testing.expectEqual(wit_types.ScalarKind.u32, value.scalar_kind().?);
}

test "WIT registry adapter converts bounded text and byte list values" {
    var binding = try wit_resolve.resolve_source(std.testing.allocator, bounded_wit_registry_source, "probe");
    defer binding.deinit();

    const text_member = try wit_registry.find_value_member(&binding, "api", "text_value");
    var text = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &text_member, .lower);
    defer text.deinit();
    try std.testing.expectEqual(wit_types.AbiTypeKind.text, text.kind());

    const bytes_member = try wit_registry.find_value_member(&binding, "api", "bytes_value");
    var bytes = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &bytes_member, .lower);
    defer bytes.deinit();
    try std.testing.expectEqual(wit_types.AbiTypeKind.list, bytes.kind());
    try std.testing.expectEqual(wit_types.ScalarKind.u8, bytes.list_element().?.scalar_kind().?);
}

test "WIT registry adapter converts bounded record fields" {
    var binding = try wit_resolve.resolve_source(std.testing.allocator, bounded_wit_registry_source, "probe");
    defer binding.deinit();
    const member = try wit_registry.find_value_member(&binding, "api", "record_value");
    var value = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &member, .lower);
    defer value.deinit();

    try std.testing.expectEqual(wit_types.AbiTypeKind.record, value.kind());
    try std.testing.expectEqual(@as(usize, 3), value.record_field_count().?);
    try std.testing.expectEqualStrings("count", value.record_field_at(0).?.name);
    try std.testing.expectEqual(wit_types.ScalarKind.u32, value.record_field_at(0).?.value.scalar_kind().?);
    try std.testing.expectEqual(wit_types.AbiTypeKind.text, value.record_field_at(1).?.value.kind());
    try std.testing.expectEqual(wit_types.AbiTypeKind.list, value.record_field_at(2).?.value.kind());
}

test "WIT registry adapter rejects unresolved, cyclic, and variant named values" {
    var binding = try wit_resolve.resolve_source(std.testing.allocator, bounded_wit_registry_source, "probe");
    defer binding.deinit();

    const unresolved = try wit_registry.find_value_member(&binding, "api", "unresolved_value");
    try std.testing.expectError(
        error.UnresolvedWitType,
        marshal_registry.resolve_member_abi_type(std.testing.allocator, &unresolved, .lower),
    );

    const cyclic = try wit_registry.find_value_member(&binding, "api", "cyclic_value");
    try std.testing.expectError(
        error.WitTypeCycle,
        marshal_registry.resolve_member_abi_type(std.testing.allocator, &cyclic, .lower),
    );

    const variant = try wit_registry.find_value_member(&binding, "api", "variant_value");
    try std.testing.expectError(
        error.UnsupportedWitMarshalShape,
        marshal_registry.resolve_member_abi_type(std.testing.allocator, &variant, .lower),
    );
}

test "WIT registry adapter selects a function result for lift" {
    var binding = try wit_resolve.resolve_source(std.testing.allocator, bounded_wit_registry_source, "probe");
    defer binding.deinit();
    const transformed = try wit_registry.find_value_member(&binding, "api", "transform_value");
    var result = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &transformed, .lift);
    defer result.deinit();
    try std.testing.expectEqual(wit_types.AbiTypeKind.text, result.kind());

    const no_result = try wit_registry.find_value_member(&binding, "api", "scalar_value");
    try std.testing.expectError(
        error.MissingWitMarshalResult,
        marshal_registry.resolve_member_abi_type(std.testing.allocator, &no_result, .lift),
    );

    var parameter = try marshal_registry.resolve_member_abi_type(std.testing.allocator, &transformed, .lower);
    defer parameter.deinit();
    try std.testing.expectEqual(wit_types.AbiTypeKind.scalar, parameter.kind());
    try std.testing.expectEqual(wit_types.ScalarKind.u32, parameter.scalar_kind().?);

    const too_many = try wit_registry.find_value_member(&binding, "api", "too_many_values");
    try std.testing.expectError(
        error.UnsupportedWitMemberArity,
        marshal_registry.resolve_member_abi_type(std.testing.allocator, &too_many, .lower),
    );
}

test "resolved WIT lower plan measures the function parameter" {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        std.testing.allocator,
        bounded_wit_registry_source,
        "probe",
        "api",
        "transform_value",
        .lower,
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    );
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(marshal.Direction.lower, plan.direction);
    try std.testing.expectEqual(marshal.NodeKind.scalar, plan.root.kind);
    try std.testing.expectEqual(@as(usize, 1), plan.abi.arguments.len);
    try std.testing.expectEqual(@as(usize, 0), plan.abi.results.len);
    try std.testing.expectEqual(abi.SlotDirection.lower, plan.abi.arguments[0].direction);
}

test "resolved WIT lift plan measures the function result" {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        std.testing.allocator,
        bounded_wit_registry_source,
        "probe",
        "api",
        "transform_value",
        .lift,
        .{ .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } } },
    );
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(marshal.Direction.lift, plan.direction);
    try std.testing.expectEqual(marshal.NodeKind.text, plan.root.kind);
    try std.testing.expectEqual(@as(u32, 8), plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(usize, 0), plan.abi.arguments.len);
    try std.testing.expectEqual(@as(usize, 1), plan.abi.results.len);
    try std.testing.expectEqual(abi.SlotDirection.lift, plan.abi.results[0].direction);
}

test "resolved WIT member builds a measured marshal plan" {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        std.testing.allocator,
        bounded_wit_registry_source,
        "probe",
        "api",
        "scalar_value",
        .lower,
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    );
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqualStrings("demo:marshal@1.0.0", plan.descriptor.package);
    try std.testing.expectEqualStrings("probe", plan.descriptor.world);
    try std.testing.expectEqualStrings("api.scalar_value", plan.descriptor.member);
    try std.testing.expectEqual(@as(usize, "sha256:".len + 64), plan.descriptor.schema_hash.len);
    try std.testing.expect(std.mem.startsWith(u8, plan.descriptor.schema_hash, "sha256:"));
    try std.testing.expectEqual(@as(u32, 4), plan.root.measured.?.byte_size);
}

const descriptor_test_source =
    \\package demo:descriptor@1.0.0;
    \\
    \\interface api {
    \\  read: func(len: u64) -> list<u8>;
    \\}
;

const descriptor_test_world =
    \\world probe { import api; }
;

fn descriptor_test_measurement() marshal.MeasuredNode {
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

fn write_descriptor_fixture(
    tmp: *std.testing.TmpDir,
    manifest_source: []const u8,
) ![]u8 {
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "random.wit", .data = descriptor_test_source });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "world.wit", .data = descriptor_test_world });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "manifest.json", .data = manifest_source });
    return tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
}

fn descriptor_manifest_json(
    allocator: std.mem.Allocator,
    source_sha256: []const u8,
    package: []const u8,
    member: []const u8,
    result: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"schema\":1,\"toolchain\":\"wasm-tools 1.255.0\",\"descriptors\":[{{\"id\":\"demo-descriptor\",\"source\":\"random.wit\",\"world_source\":\"world.wit\",\"package\":\"{s}\",\"world\":\"probe\",\"interface\":\"api\",\"member\":\"{s}\",\"direction\":\"lift\",\"params\":[\"u64\"],\"result\":\"{s}\",\"source_sha256\":\"{s}\",\"canonical_import\":{{\"module\":\"demo:descriptor/api@1.0.0\",\"name\":\"read\"}}}}]}}", .{ package, member, result, source_sha256 });
}

fn descriptor_source_hash(buffer: *[71]u8) []const u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    var combined: [descriptor_test_source.len + 1 + descriptor_test_world.len + 1]u8 = undefined;
    var offset: usize = 0;
    @memcpy(combined[offset .. offset + descriptor_test_source.len], descriptor_test_source);
    offset += descriptor_test_source.len;
    combined[offset] = '\n';
    offset += 1;
    @memcpy(combined[offset .. offset + descriptor_test_world.len], descriptor_test_world);
    offset += descriptor_test_world.len;
    combined[offset] = '\n';
    std.crypto.hash.sha2.Sha256.hash(&combined, &digest, .{});
    @memcpy(buffer[0..7], "sha256:");
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        buffer[7 + index * 2] = digits[byte >> 4];
        buffer[7 + index * 2 + 1] = digits[byte & 0x0f];
    }
    return buffer[0..];
}

test "descriptor loader resolves a hash-pinned random member" {
    var hash: [71]u8 = undefined;
    const manifest_source = try descriptor_manifest_json(std.testing.allocator, descriptor_source_hash(&hash), "demo:descriptor@1.0.0", "read", "list<u8>");
    defer std.testing.allocator.free(manifest_source);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try write_descriptor_fixture(&tmp, manifest_source);
    defer std.testing.allocator.free(root.ptr[0 .. root.len + 1]);

    var loaded = try descriptor_loader.load_request(
        std.testing.io,
        std.testing.allocator,
        root,
        "manifest.json",
        "demo-descriptor",
        descriptor_test_measurement(),
        16,
    );
    defer loaded.deinit();
    try std.testing.expectEqualStrings("probe", loaded.request.world_name);
    try std.testing.expectEqualStrings("api", loaded.request.interface_name);
    try std.testing.expectEqualStrings("read", loaded.request.member_name);
    try std.testing.expectEqual(marshal.Direction.lift, loaded.request.direction);
    try std.testing.expectEqual(@as(?u64, 16), loaded.request.canonical_u64_arg);

    const wat = try marshal_route.emit_sync_marshal_module_from_wit_source(std.testing.allocator, loaded.request);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:descriptor/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i64 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 16") != null);
}

test "descriptor loader decodes the manifest-owned managed record layout" {
    var loaded = try descriptor_loader.load_request_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-managed-lower/api.write@1.0.0/lower",
        null,
    );
    defer loaded.deinit();
    switch (loaded.request.measured.layout) {
        .record => |record| {
            try std.testing.expectEqual(@as(u32, 12), record.byte_size);
            try std.testing.expectEqual(@as(usize, 2), record.fields.len);
            try std.testing.expectEqualStrings("label", record.fields[1].name);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "descriptor loader derives the managed host boundary from WIT" {
    const source = @embedFile("test/compile_ok/565_gc_wit_managed_record_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try descriptor_loader.validate_host_boundary_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-managed-lower/api.write@1.0.0/lower",
        tokens,
    );
}

test "descriptor loader derives the bounded byte-list host boundary from WIT" {
    const source = @embedFile("test/compile_ok/592_gc_wit_record_byte_list_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try descriptor_loader.validate_host_boundary_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-byte-list-lower/api.write@1.0.0/lower",
        tokens,
    );
}

test "descriptor loader derives the bounded u32-list host boundary from WIT" {
    const source = @embedFile("test/compile_ok/601_gc_wit_record_u32_list_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try descriptor_loader.validate_host_boundary_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-u32-list-lower/api.write@1.0.0/lower",
        tokens,
    );
}

test "descriptor loader derives the mixed text u32-list host boundary from WIT" {
    const source = @embedFile("test/compile_ok/630_gc_wit_mixed_text_u32_list_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try descriptor_loader.validate_host_boundary_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower",
        tokens,
    );
}

test "descriptor loader derives the mixed text u32-list lift plan" {
    const source = @embedFile("test/compile_ok/639_gc_wit_mixed_text_u32_list_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try descriptor_loader.validate_host_boundary_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift",
        tokens,
    );

    var loaded = try descriptor_loader.load_request_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift",
        null,
    );
    defer loaded.deinit();

    const memory_plan = try marshal_ops.build_sync_memory_plan(&loaded.plan);
    try std.testing.expectEqual(marshal.Direction.lift, memory_plan.direction);
    try std.testing.expectEqual(@as(u32, 3), memory_plan.record_field_count);
    try std.testing.expectEqual(@as(u32, 20), loaded.plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.measured.?.alignment);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[1].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 12), loaded.plan.root.children[2].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[2].measured.?.element_stride.?);
    try std.testing.expectEqual(@as(u32, 3), loaded.plan.root.children[2].measured.?.capacity.?);
    const expected = [_]marshal_ops.MemoryOperation{
        .canonical_call,
        .validate_linear_range,
        .copy_from_linear,
        .construct_gc_value,
        .publish_gc_root,
    };
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &expected, memory_plan.operations);
}

test "descriptor loader derives the mixed text byte-list lift plan" {
    const source = @embedFile("test/compile_ok/648_gc_wit_mixed_text_byte_list_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try descriptor_loader.validate_host_boundary_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift",
        tokens,
    );

    var loaded = try descriptor_loader.load_request_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift",
        null,
    );
    defer loaded.deinit();

    const memory_plan = try marshal_ops.build_sync_memory_plan(&loaded.plan);
    try std.testing.expectEqual(marshal.Direction.lift, memory_plan.direction);
    try std.testing.expectEqual(@as(u32, 3), memory_plan.record_field_count);
    try std.testing.expectEqual(@as(u32, 20), loaded.plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.measured.?.alignment);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[1].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 12), loaded.plan.root.children[2].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 1), loaded.plan.root.children[2].measured.?.element_stride.?);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[2].measured.?.capacity.?);
    const expected = [_]marshal_ops.MemoryOperation{
        .canonical_call,
        .validate_linear_range,
        .copy_from_linear,
        .construct_gc_value,
        .publish_gc_root,
    };
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &expected, memory_plan.operations);
}

test "descriptor loader derives the mixed text and two u32-list lift plan" {
    const source = @embedFile("test/compile_ok/673_gc_wit_mixed_text_two_u32_lists_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const descriptor_id = "demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift";
    try descriptor_loader.validate_host_boundary_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        descriptor_id,
        tokens,
    );

    var loaded = try descriptor_loader.load_request_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        descriptor_id,
        null,
    );
    defer loaded.deinit();

    try std.testing.expectEqual(marshal.Direction.lift, loaded.plan.direction);
    try std.testing.expectEqual(@as(usize, 1), loaded.plan.abi.results.len);
    try std.testing.expectEqualStrings("memory", loaded.plan.abi.results[0].canonical_type);
    try std.testing.expect(!loaded.plan.contains_gc_reference);

    const root = loaded.plan.root.measured orelse unreachable;
    try std.testing.expectEqual(@as(u32, 28), root.byte_size);
    try std.testing.expectEqual(@as(u32, 4), root.alignment);
    try std.testing.expectEqual(@as(usize, 4), loaded.plan.root.children.len);
    try std.testing.expectEqual(@as(u32, 0), loaded.plan.root.children[0].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[1].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 12), loaded.plan.root.children[2].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 20), loaded.plan.root.children[3].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[2].measured.?.element_stride.?);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[3].measured.?.element_stride.?);
    try std.testing.expectEqual(@as(u32, 3), loaded.plan.root.children[2].measured.?.capacity.?);
    try std.testing.expectEqual(@as(u32, 2), loaded.plan.root.children[3].measured.?.capacity.?);

    const descriptor = try loaded.manifest.find_descriptor(descriptor_id);
    const measured_layout = descriptor.measured_layout orelse unreachable;
    const first = measured_layout.children[2];
    const second = measured_layout.children[3];
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 1, 2, 3 }, first.accepted_lengths);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 1, 2 }, second.accepted_lengths);

    const memory_plan = try marshal_ops.build_sync_memory_plan(&loaded.plan);
    try std.testing.expectEqual(@as(u32, 4), memory_plan.record_field_count);
    try std.testing.expect(memory_plan.record_mixed_text_two_u32_lists_lift);
    const expected = [_]marshal_ops.MemoryOperation{
        .canonical_call,
        .validate_linear_range,
        .validate_linear_range,
        .validate_linear_range,
        .validate_linear_range,
        .copy_from_linear,
        .copy_from_linear,
        .copy_from_linear,
        .construct_gc_value,
        .publish_gc_root,
        .cabi_realloc_free,
        .cabi_realloc_free,
        .cabi_realloc_free,
    };
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &expected, memory_plan.operations);
}

test "descriptor loader rejects source hash drift before planning" {
    var hash: [71]u8 = undefined;
    const manifest_source = try descriptor_manifest_json(std.testing.allocator, descriptor_source_hash(&hash), "demo:descriptor@1.0.0", "read", "list<u8>");
    defer std.testing.allocator.free(manifest_source);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "random.wit", .data = descriptor_test_source ++ "\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "world.wit", .data = descriptor_test_world });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "manifest.json", .data = manifest_source });
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root.ptr[0 .. root.len + 1]);

    try std.testing.expectError(error.SourceHashMismatch, descriptor_loader.load_request(
        std.testing.io,
        std.testing.allocator,
        root,
        "manifest.json",
        "demo-descriptor",
        descriptor_test_measurement(),
        null,
    ));
}

test "descriptor loader rejects package and signature drift" {
    var hash: [71]u8 = undefined;
    const package_manifest = try descriptor_manifest_json(std.testing.allocator, descriptor_source_hash(&hash), "demo:other@1.0.0", "read", "list<u8>");
    defer std.testing.allocator.free(package_manifest);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try write_descriptor_fixture(&tmp, package_manifest);
    defer std.testing.allocator.free(root.ptr[0 .. root.len + 1]);
    try std.testing.expectError(error.PackageMismatch, descriptor_loader.load_request(
        std.testing.io,
        std.testing.allocator,
        root,
        "manifest.json",
        "demo-descriptor",
        descriptor_test_measurement(),
        null,
    ));

    const signature_manifest = try descriptor_manifest_json(std.testing.allocator, descriptor_source_hash(&hash), "demo:descriptor@1.0.0", "read", "list<u16>");
    defer std.testing.allocator.free(signature_manifest);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "manifest.json", .data = signature_manifest });
    try std.testing.expectError(error.SignatureMismatch, descriptor_loader.load_request(
        std.testing.io,
        std.testing.allocator,
        root,
        "manifest.json",
        "demo-descriptor",
        descriptor_test_measurement(),
        null,
    ));
}

test "descriptor loader rejects member and canonical import drift" {
    var hash: [71]u8 = undefined;
    const member_manifest = try descriptor_manifest_json(std.testing.allocator, descriptor_source_hash(&hash), "demo:descriptor@1.0.0", "other", "list<u8>");
    defer std.testing.allocator.free(member_manifest);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try write_descriptor_fixture(&tmp, member_manifest);
    defer std.testing.allocator.free(root.ptr[0 .. root.len + 1]);
    try std.testing.expectError(error.MemberMismatch, descriptor_loader.load_request(
        std.testing.io,
        std.testing.allocator,
        root,
        "manifest.json",
        "demo-descriptor",
        descriptor_test_measurement(),
        null,
    ));

    const canonical_marker = "demo:descriptor/api@1.0.0";
    const canonical_manifest = try descriptor_manifest_json(std.testing.allocator, descriptor_source_hash(&hash), "demo:descriptor@1.0.0", "read", "list<u8>");
    defer std.testing.allocator.free(canonical_manifest);
    const drifted = try std.mem.replaceOwned(u8, std.testing.allocator, canonical_manifest, canonical_marker, "demo:wrong/api@1.0.0");
    defer std.testing.allocator.free(drifted);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "manifest.json", .data = drifted });
    try std.testing.expectError(error.CanonicalImportMismatch, descriptor_loader.load_request(
        std.testing.io,
        std.testing.allocator,
        root,
        "manifest.json",
        "demo-descriptor",
        descriptor_test_measurement(),
        null,
    ));
}

test "descriptor loader rejects unsupported WIT shapes" {
    const source =
        \\package demo:descriptor@1.0.0;
        \\
        \\interface api { read: func() -> option<u8>; }
    ;
    const world =
        \\world probe { import api; }
    ;
    var combined: [source.len + 1 + world.len + 1]u8 = undefined;
    var offset: usize = 0;
    @memcpy(combined[offset .. offset + source.len], source);
    offset += source.len;
    combined[offset] = '\n';
    offset += 1;
    @memcpy(combined[offset .. offset + world.len], world);
    offset += world.len;
    combined[offset] = '\n';
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&combined, &digest, .{});
    var hash: [71]u8 = undefined;
    @memcpy(hash[0..7], "sha256:");
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        hash[7 + index * 2] = digits[byte >> 4];
        hash[7 + index * 2 + 1] = digits[byte & 0x0f];
    }
    const manifest_source = try std.fmt.allocPrint(std.testing.allocator, "{{\"schema\":1,\"toolchain\":\"wasm-tools 1.255.0\",\"descriptors\":[{{\"id\":\"demo-descriptor\",\"source\":\"random.wit\",\"world_source\":\"world.wit\",\"package\":\"demo:descriptor@1.0.0\",\"world\":\"probe\",\"interface\":\"api\",\"member\":\"read\",\"direction\":\"lift\",\"params\":[],\"result\":\"option<u8>\",\"source_sha256\":\"{s}\",\"canonical_import\":{{\"module\":\"demo:descriptor/api@1.0.0\",\"name\":\"read\"}}}}]}}", .{hash[0..]});
    defer std.testing.allocator.free(manifest_source);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "random.wit", .data = source });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "world.wit", .data = world });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "manifest.json", .data = manifest_source });
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root.ptr[0 .. root.len + 1]);
    try std.testing.expectError(error.UnsupportedWitShape, descriptor_loader.load_request(
        std.testing.io,
        std.testing.allocator,
        root,
        "manifest.json",
        "demo-descriptor",
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        null,
    ));
}

test "resolved WIT member rejects measured layout drift" {
    try std.testing.expectError(
        error.ScalarTypeMismatch,
        marshal_registry.build_sync_value_plan_from_wit_source(
            std.testing.allocator,
            bounded_wit_registry_source,
            "probe",
            "api",
            "scalar_value",
            .lower,
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        ),
    );
}

test "WIT source adapter resolves parser input before building the plan" {
    const plan = try marshal_registry.build_sync_value_plan_from_wit_source(
        std.testing.allocator,
        bounded_wit_registry_source,
        "probe",
        "api",
        "scalar_value",
        .lower,
        .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
    );
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqualStrings("demo:marshal@1.0.0", plan.descriptor.package);
    try std.testing.expectEqualStrings("api.scalar_value", plan.descriptor.member);
}

test "canonical marshal descriptor binding rejects a malformed schema hash" {
    var text = wit_types.AbiType.text(std.testing.allocator);
    defer text.deinit();

    try std.testing.expectError(
        error.InvalidDescriptorIdentity,
        marshal.validate_descriptor_binding(.{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "send",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "x",
        }, .{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "send",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        }),
    );
}

test "canonical marshal descriptor binding rejects registry drift before plan construction" {
    var text = wit_types.AbiType.text(std.testing.allocator);
    defer text.deinit();

    try std.testing.expectError(
        error.DescriptorDrift,
        marshal.build_sync_value_plan_with_registry(std.testing.allocator, .{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "send",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        }, .{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "send",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "sha256:2222222222222222222222222222222222222222222222222222222222222222",
        }, &text, .lower),
    );
}

test "canonical marshal plan accounts for wide scalar field size" {
    var prefix = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer prefix.deinit();
    var wide = wit_types.AbiType.scalar(std.testing.allocator, .u64);
    defer wide.deinit();
    var suffix = wit_types.AbiType.text(std.testing.allocator);
    defer suffix.deinit();
    var record = try wit_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "prefix", .value = &prefix },
        .{ .name = "wide", .value = &wide },
        .{ .name = "suffix", .value = &suffix },
    });
    defer record.deinit();

    const plan = try marshal.build_sync_value_plan(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "wide",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:wide-v1",
    }, &record, .lower);
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(@as(u32, 0), plan.root.children[0].provisional_offset);
    try std.testing.expectEqual(@as(u32, 8), plan.root.children[1].provisional_offset);
    try std.testing.expectEqual(@as(u32, 16), plan.root.children[2].provisional_offset);
}

test "canonical marshal plan binds measured scalar layout facts" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .i64);
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "read",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:read-i64-v1",
    }, &value, .lower, .{
        .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expect(plan.root.measured != null);
    try std.testing.expectEqual(@as(u32, 16), plan.root.measured.?.offset);
    try std.testing.expectEqual(@as(u32, 8), plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(u32, 8), plan.root.measured.?.alignment);
    try std.testing.expect(plan.root.measured.?.element_stride == null);
}

test "canonical marshal plan binds measured text layout facts" {
    var value = wit_types.AbiType.text(std.testing.allocator);
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-text-v2",
    }, &value, .lower, .{
        .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(@as(u32, 8), plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(u32, 4), plan.root.measured.?.alignment);
}

test "canonical marshal plan binds measured byte list layout facts" {
    var byte = wit_types.AbiType.scalar(std.testing.allocator, .u8);
    defer byte.deinit();
    var value = try wit_types.AbiType.list(std.testing.allocator, &byte);
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:write-bytes-v1",
    }, &value, .lower, .{
        .layout = .{ .byte_list = .{
            .pointer_offset = 64,
            .length_offset = 68,
            .element_byte_size = 1,
            .element_stride = 1,
            .element_alignment = 1,
            .capacity = 4,
            .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(@as(u32, 8), plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(u32, 1), plan.root.measured.?.element_stride.?);
    try std.testing.expectEqual(@as(u32, 1), plan.root.children[0].measured.?.byte_size);
}

test "canonical marshal plan rejects measured scalar layout drift" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .i64);
    defer value.deinit();

    try std.testing.expectError(
        error.ScalarTypeMismatch,
        marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "read",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "sha256:read-i64-v1",
        }, &value, .lower, .{
            .layout = .{ .scalar = .{ .offset = 16, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
        }),
    );
}

test "canonical marshal plan binds measured record fields and list stride" {
    var count = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer count.deinit();
    var values = try wit_types.AbiType.list(std.testing.allocator, &count);
    defer values.deinit();
    var record = try wit_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "count", .value = &count },
        .{ .name = "values", .value = &values },
    });
    defer record.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "batch",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:batch-v2",
    }, &record, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 16,
            .alignment = 8,
            .fields = &.{
                .{ .name = "count", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "values", .offset = 8, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 4,
                .element_stride = 8,
                .element_alignment = 4,
                .ticket_offset = 0,
                .capacity = 3,
                .accepted_lengths = &.{ 0, 1, 2, 3 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } }} },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(@as(u32, 16), plan.root.measured.?.byte_size);
    try std.testing.expectEqual(@as(u32, 8), plan.root.children[1].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 8), plan.root.children[1].measured.?.element_stride.?);
}

test "canonical marshal ops admit the bounded record byte-list lower shape" {
    var code = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var byte = wit_types.AbiType.scalar(std.testing.allocator, .u8);
    defer byte.deinit();
    var payload = try wit_types.AbiType.list(std.testing.allocator, &byte);
    defer payload.deinit();
    var record = try wit_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "payload", .value = &payload },
    });
    defer record.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-byte-list-lower@1.0.0",
        .world = "probe",
        .member = "write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:byte-list-record-lower-v1",
    }, &record, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 12,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "payload", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
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
                .capacity = 4,
                .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const ops = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(marshal_ops.CopyShape.record_fields, ops.copy_shape);
    try std.testing.expectEqual(@as(u32, 2), ops.record_field_count);
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &.{
        .read_gc_span,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .canonical_call,
        .cabi_realloc_free,
    }, ops.operations);
}

test "canonical marshal plan rejects indirect record fields before emission" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var record = try wit_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "value", .value = &value },
    });
    defer record.deinit();

    try std.testing.expectError(
        error.UnsupportedMeasuredShape,
        marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
            .package = "example:host@0.1.0",
            .world = "host",
            .member = "write",
            .revision = "wasm-tools-1.255.0",
            .schema_hash = "sha256:indirect-record-v1",
        }, &record, .lower, .{
            .layout = .{ .record = .{
                .byte_size = 4,
                .alignment = 4,
                .fields = &.{.{
                    .name = "value",
                    .offset = 0,
                    .byte_size = 4,
                    .alignment = 4,
                    .indirect = .{
                        .core_words = &.{.i32},
                        .allocation = .cabi_realloc,
                        .free = .cabi_realloc,
                    },
                }},
            } },
            .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }},
        }),
    );
}

test "canonical marshal ops admit a measured indirect scalar record lower" {
    const field_names = [_][]const u8{
        "f0", "f1",  "f2",  "f3",  "f4",  "f5",  "f6",  "f7",  "f8",
        "f9", "f10", "f11", "f12", "f13", "f14", "f15", "f16",
    };
    var scalar = wit_types.AbiType.scalar(std.testing.allocator, .u64);
    defer scalar.deinit();
    var specs: [field_names.len]wit_types.FieldSpec = undefined;
    var fields: [field_names.len]wit_layout.FieldMeasurement = undefined;
    var children: [field_names.len]marshal.MeasuredNode = undefined;
    for (field_names, 0..) |name, index| {
        specs[index] = .{ .name = name, .value = &scalar };
        fields[index] = .{
            .name = name,
            .offset = @intCast(index * 8),
            .byte_size = 8,
            .alignment = 8,
            .indirect = null,
        };
        children[index] = .{ .layout = .{ .scalar = .{
            .offset = 0,
            .byte_size = 8,
            .alignment = 8,
            .core_type = .i64,
        } } };
    }
    var record = try wit_types.AbiType.record(std.testing.allocator, &specs);
    defer record.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-indirect@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:indirect-record-v1",
    }, &record, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 136,
            .alignment = 8,
            .fields = &fields,
            .indirect = .{
                .core_words = &.{.i32},
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            },
        } },
        .children = &children,
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(marshal_ops.CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expectEqual(wit_layout.CoreWord.i32, memory_plan.record_indirect.?.core_words[0]);
    try std.testing.expectEqual(@as(usize, 6), memory_plan.operations.len);
    try std.testing.expectEqual(marshal_ops.MemoryOperation.read_gc_span, memory_plan.operations[0]);
    try std.testing.expectEqual(marshal_ops.MemoryOperation.cabi_realloc_alloc, memory_plan.operations[2]);
    try std.testing.expectEqual(marshal_ops.MemoryOperation.canonical_call, memory_plan.operations[4]);
    try std.testing.expectEqual(marshal_ops.MemoryOperation.cabi_realloc_free, memory_plan.operations[5]);
}

test "canonical marshal ops lower measured text in a fixed safe order" {
    var value = wit_types.AbiType.text(std.testing.allocator);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-text-v3",
    }, &value, .lower, .{
        .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const ops = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(marshal.Direction.lower, ops.direction);
    try std.testing.expectEqual(marshal_ops.CopyShape.text_bytes, ops.copy_shape);
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &.{
        .read_gc_span,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .canonical_call,
        .cabi_realloc_free,
    }, ops.operations);
}

test "canonical marshal ops lower measured scalar directly without linear allocation" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send-value",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-value-v1",
    }, &value, .lower, .{
        .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const ops = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(marshal_ops.CopyShape.scalar, ops.copy_shape);
    try std.testing.expectEqual(wit_layout.CoreWord.i32, ops.scalar_core_type.?);
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &.{
        .canonical_call,
    }, ops.operations);
    try std.testing.expectEqualStrings("i32", plan.abi.arguments[0].canonical_type);
    try std.testing.expect(!plan.abi.arguments[0].contains_gc_reference);
}

test "canonical marshal ops lift measured scalar directly without linear allocation" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .i64);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "receive-value",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:receive-value-v1",
    }, &value, .lift, .{
        .layout = .{ .scalar = .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .i64 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const ops = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(marshal_ops.CopyShape.scalar, ops.copy_shape);
    try std.testing.expectEqual(wit_layout.CoreWord.i64, ops.scalar_core_type.?);
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &.{
        .canonical_call,
    }, ops.operations);
    try std.testing.expectEqualStrings("i64", plan.abi.results[0].canonical_type);
    try std.testing.expect(!plan.abi.results[0].contains_gc_reference);
}

test "canonical marshal ops preserve f64 as a float core word" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .f64);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send-float",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-float-v1",
    }, &value, .lower, .{
        .layout = .{ .scalar = .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .f64 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const ops = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(wit_layout.CoreWord.f64, ops.scalar_core_type.?);
    try std.testing.expectEqualStrings("f64", plan.abi.arguments[0].canonical_type);
}

test "canonical marshal ops preserve f32 as a float core word" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .f32);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send-float",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-float-v2",
    }, &value, .lower, .{
        .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .f32 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const ops = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(wit_layout.CoreWord.f32, ops.scalar_core_type.?);
    try std.testing.expectEqualStrings("f32", plan.abi.arguments[0].canonical_type);
    const wat = try marshal_wat.emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .canonical_call_name = "host_call",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input f32)") != null);
}

test "canonical marshal WAT lower measured scalar emits a direct core call" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send-value",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-value-v1",
    }, &value, .lower, .{
        .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try marshal_wat.emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .canonical_call_name = "host_call",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $marshal (param $input i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $input") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $host_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "cabi_realloc") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "ref null") == null);
}

test "canonical marshal WAT lift measured scalar emits a direct core result" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .i64);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "receive-value",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:receive-value-v1",
    }, &value, .lift, .{
        .layout = .{ .scalar = .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .i64 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try marshal_wat.emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .canonical_call_name = "host_call",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $marshal (result i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $host_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "cabi_realloc") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "ref null") == null);
}

test "canonical marshal module emits scalar ABI without linear allocation" {
    var value = wit_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send-value",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    }, &value, .lower, .{
        .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const module_wat = try marshal_module.emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal/api@1.0.0",
        .canonical_import_name = "send-value",
    });
    defer std.testing.allocator.free(module_wat);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(type $canonical_lower (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(type $do_bytes") == null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "cabi_realloc") == null);
    try std.testing.expect(std.mem.indexOf(u8, module_wat, "(ref") == null);
}

test "canonical marshal ops lift measured byte list without exposing GC refs" {
    var byte = wit_types.AbiType.scalar(std.testing.allocator, .u8);
    defer byte.deinit();
    var value = try wit_types.AbiType.list(std.testing.allocator, &byte);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "receive",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:receive-bytes-v1",
    }, &value, .lift, .{
        .layout = .{ .byte_list = .{
            .pointer_offset = 64,
            .length_offset = 68,
            .element_byte_size = 1,
            .element_stride = 1,
            .element_alignment = 1,
            .capacity = 4,
            .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const ops = try marshal_ops.build_sync_memory_plan(&plan);
    try std.testing.expectEqual(marshal.Direction.lift, ops.direction);
    try std.testing.expectEqual(marshal_ops.CopyShape.list_elements, ops.copy_shape);
    try std.testing.expectEqual(@as(u32, 1), ops.element_stride);
    try std.testing.expectEqualSlices(marshal_ops.MemoryOperation, &.{
        .canonical_call,
        .validate_linear_range,
        .copy_from_linear,
        .construct_gc_value,
        .publish_gc_root,
        .cabi_realloc_free,
    }, ops.operations);
}

test "canonical marshal ops reject a plan without measured layout" {
    var value = wit_types.AbiType.text(std.testing.allocator);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-text-unmeasured",
    }, &value, .lower);
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectError(error.MeasuredLayoutRequired, marshal_ops.build_sync_memory_plan(&plan));
}

test "canonical marshal ops reject a GC reference hidden in the marshal tree" {
    var value = wit_types.AbiType.text(std.testing.allocator);
    defer value.deinit();
    var plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "send",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:send-text-v1",
    }, &value, .lower, .{
        .layout = .{ .text = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);
    plan.root.contains_gc_reference = true;
    try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, marshal_ops.build_sync_memory_plan(&plan));
}

test "canonical marshal ops validate pointer length spans without overflow" {
    try marshal_ops.validate_linear_span(8, 4, 16);
    try std.testing.expectError(error.PointerOutOfBounds, marshal_ops.validate_linear_span(17, 0, 16));
    try std.testing.expectError(error.LengthOutOfBounds, marshal_ops.validate_linear_span(15, 2, 16));
    try std.testing.expectError(error.CopyByteCountOverflow, marshal_ops.copy_byte_count(std.math.maxInt(u32), 2));
}
