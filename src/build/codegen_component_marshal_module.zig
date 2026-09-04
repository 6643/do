//! Bounded core-module assembly for measured synchronous marshal plans.
//!
//! This module owns only the core wrapper needed to validate a small
//! canonical-memory probe. It deliberately does not assemble a host runtime,
//! infer arbitrary WIT names, or expose GC references at the component ABI.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const marshal_wat = @import("codegen_component_marshal_wat.zig");
const marshal_ops = @import("codegen_component_marshal_ops.zig");
const runtime_gc_wat = @import("runtime_gc_wat.zig");

pub const EmitConfig = struct {
    direction: marshal.Direction,
    function_name: []const u8 = "marshal",
    export_name: []const u8 = "marshal",
    input_local: []const u8 = "input",
    realloc_name: []const u8 = "cabi_realloc",
    canonical_call_name: []const u8 = "canonical_call",
    canonical_import_module: []const u8,
    canonical_import_name: []const u8,
    /// Fixed scalar argument used by the bounded WASI random-bytes lift.
    canonical_u64_arg: ?u64 = null,
    /// Optional probe instrumentation for counting temporary linear spans.
    emit_realloc_counters: bool = false,
    memory_min_pages: u32 = 1,
};

pub fn emit_sync_marshal_module(
    allocator: std.mem.Allocator,
    plan: *const marshal.SyncValuePlan,
    config: EmitConfig,
) ![]u8 {
    const memory_plan = try marshal_ops.build_sync_memory_plan(plan);
    try validate_config(allocator, plan, config, &memory_plan);
    const uses_linear_memory = switch (memory_plan.copy_shape) {
        .scalar => false,
        .text_bytes, .list_elements, .map_entries => true,
        .record_fields => memory_plan.direction == .lift or
            memory_plan.record_indirect != null or
            memory_plan.record_managed_text_lower or
            memory_plan.record_managed_scalar_list_lower or
            memory_plan.record_managed_scalar_list_pair_lower or
            memory_plan.record_managed_text_scalar_list_pair_lower or
            memory_plan.record_managed_text_byte_u32_list_lower or
            memory_plan.record_managed_mixed_scalar_list_lower,
    };
    const uses_realloc = switch (memory_plan.copy_shape) {
        .text_bytes, .list_elements, .map_entries => true,
        .record_fields => memory_plan.record_indirect != null or
            memory_plan.record_managed_text_lower or
            memory_plan.record_managed_scalar_list_lower or
            memory_plan.record_managed_scalar_list_pair_lower or
            memory_plan.record_managed_text_scalar_list_pair_lower or
            memory_plan.record_managed_text_byte_u32_list_lower or
            memory_plan.record_managed_mixed_scalar_list_lower or
            (memory_plan.direction == .lift and
                (marshal_ops.record_contains_text(&plan.root) or marshal_ops.record_contains_list(&plan.root))),
        .scalar => false,
    };

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "(module\n");
    if (uses_linear_memory) {
        try runtime_gc_wat.emit_bytes_type(allocator, &out);
        try runtime_gc_wat.emit_text_type(allocator, &out);
        if (memory_plan.element_core_type != null or
            memory_plan.copy_shape == .map_entries or
            (memory_plan.managed_scalar_list_field != null and
                memory_plan.managed_scalar_list_field.?.element_kind == .u32) or
            memory_plan.managed_scalar_list_pair_lower != null or
            memory_plan.managed_text_scalar_list_pair_lower != null or
            memory_plan.managed_text_byte_u32_list_lower != null or
            (memory_plan.direction == .lift and marshal_ops.record_contains_u32_list(&plan.root)))
        {
            try runtime_gc_wat.emit_u32_type(allocator, &out);
        }
        if (memory_plan.copy_shape == .map_entries) {
            const map_value_type = try map_gc_value_array_type(plan);
            if (std.mem.eql(u8, map_value_type, "$do_text_array")) {
                try runtime_gc_wat.emit_managed_array_type(allocator, &out, "$do_text_array", "text", &.{});
            }
            try runtime_gc_wat.emit_map_type_for_value(allocator, &out, map_value_type);
        }
    }
    if (memory_plan.copy_shape == .record_fields) {
        try emit_record_type(allocator, &out, plan);
    }
    try emit_canonical_import_type(allocator, &out, config.direction, &memory_plan, plan, config);
    if (uses_realloc) {
        try out.appendSlice(allocator, "  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))\n");
    }
    try generated_text.append_fmt(allocator, &out,
        "  (import \"{[canonical_import_module]s}\" \"{[canonical_import_name]s}\" (func ${[canonical_call_name]s} (type $canonical_{[direction]s})))\n",
        .{
        .canonical_import_module = config.canonical_import_module,
        .canonical_import_name = config.canonical_import_name,
        .canonical_call_name = config.canonical_call_name,
        .direction = direction_name(config.direction),
    });
    if (uses_linear_memory) {
        try generated_text.append_fmt(allocator, &out, "  (memory (export \"memory\") {[memory_min_pages]d})\n", .{ .memory_min_pages = config.memory_min_pages });
        if (uses_realloc) {
            const heap_start = try marshal_heap_start(plan);
            try generated_text.append_fmt(allocator, &out,
                "  (global $__marshal_heap (mut i32) (i32.const {[heap_start]d}))\n",
                .{ .heap_start = heap_start },
            );
            if (config.emit_realloc_counters) {
                try generated_text.append_block(allocator, &out, 2,
                    \\  (global $__alloc_count (mut i32) (i32.const 0))
                    \\  (global $__free_count (mut i32) (i32.const 0))
                    \\
                );
            }
            try emit_realloc(allocator, &out, config.realloc_name, config.emit_realloc_counters);
        }
    }

    const function_wat = try marshal_wat.emit_sync_marshal_function(allocator, plan, .{
        .function_name = config.function_name,
        .input_local = config.input_local,
        .realloc_name = config.realloc_name,
        .canonical_call_name = config.canonical_call_name,
        .canonical_u64_arg = config.canonical_u64_arg,
    });
    defer allocator.free(function_wat);
    try out.appendSlice(allocator, function_wat);
    try generated_text.append_fmt(allocator, &out, "  (export \"{[export_name]s}\" (func ${[function_name]s}))\n", .{ .export_name = config.export_name, .function_name = config.function_name });
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

/// Emit only the canonical import and linear-memory support needed by a
/// marshal helper embedded in an existing GC module. The caller is
/// responsible for emitting the GC object types and the helper body itself.
/// This keeps the ordinary-call route on the same measured plan as the
/// standalone probe without nesting a second `(module ...)`.
pub fn emit_sync_marshal_gc_support(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    config: EmitConfig,
) !void {
    try marshal.validate_sync_value_plan(plan);
    const memory_plan = try marshal_ops.build_sync_memory_plan(plan);
    try validate_config(allocator, plan, config, &memory_plan);
    const uses_linear_memory = switch (memory_plan.copy_shape) {
        .scalar => false,
        .text_bytes, .list_elements, .map_entries => true,
        .record_fields => memory_plan.direction == .lift or
            memory_plan.record_indirect != null or
            memory_plan.record_managed_text_lower or
            memory_plan.record_managed_scalar_list_lower or
            memory_plan.record_managed_scalar_list_pair_lower or
            memory_plan.record_managed_text_scalar_list_pair_lower or
            memory_plan.record_managed_text_byte_u32_list_lower or
            memory_plan.record_managed_mixed_scalar_list_lower,
    };
    const uses_realloc = switch (memory_plan.copy_shape) {
        .text_bytes, .list_elements, .map_entries => true,
        .record_fields => memory_plan.record_indirect != null or
            memory_plan.record_managed_text_lower or
            memory_plan.record_managed_scalar_list_lower or
            memory_plan.record_managed_scalar_list_pair_lower or
            memory_plan.record_managed_text_scalar_list_pair_lower or
            memory_plan.record_managed_text_byte_u32_list_lower or
            memory_plan.record_managed_mixed_scalar_list_lower or
            (memory_plan.direction == .lift and
                (marshal_ops.record_contains_text(&plan.root) or marshal_ops.record_contains_list(&plan.root))),
        .scalar => false,
    };

    try emit_canonical_import_type(allocator, out, config.direction, &memory_plan, plan, config);
    if (uses_realloc) {
        try out.appendSlice(allocator, "  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))\n");
    }
    try generated_text.append_fmt(allocator, out,
        "  (import \"{[canonical_import_module]s}\" \"{[canonical_import_name]s}\" (func ${[canonical_call_name]s} (type $canonical_{[direction]s})))\n",
        .{
        .canonical_import_module = config.canonical_import_module,
        .canonical_import_name = config.canonical_import_name,
        .canonical_call_name = config.canonical_call_name,
        .direction = direction_name(config.direction),
    });
    if (!uses_linear_memory) return;
    try generated_text.append_fmt(allocator, out, "  (memory (export \"memory\") {[memory_min_pages]d})\n", .{ .memory_min_pages = config.memory_min_pages });
    if (uses_realloc) {
        const heap_start = try marshal_heap_start(plan);
        try generated_text.append_fmt(allocator, out,
            "  (global $__marshal_heap (mut i32) (i32.const {[heap_start]d}))\n",
            .{ .heap_start = heap_start },
        );
        try emit_realloc(allocator, out, config.realloc_name, config.emit_realloc_counters);
    }
}

fn marshal_heap_start(plan: *const marshal.SyncValuePlan) !u32 {
    if (plan.direction != .lift) return 16;
    const root = plan.root.measured orelse return error.MeasuredRootMissing;
    const result_end = std.math.add(u32, root.offset, root.byte_size) catch return error.OffsetOverflow;
    const aligned_end = std.math.add(u32, result_end, 3) catch return error.OffsetOverflow;
    return @max(@as(u32, 16), aligned_end & ~@as(u32, 3));
}

fn map_gc_value_array_type(plan: *const marshal.SyncValuePlan) ![]const u8 {
    if (plan.root.kind != .map or plan.root.children.len != 2) return error.UnsupportedMarshalShape;
    const value = &plan.root.children[1];
    return switch (value.kind) {
        .scalar => if (value.scalar_kind == .u32) "$do_u32" else error.UnsupportedMarshalShape,
        .text => "$do_text_array",
        else => error.UnsupportedMarshalShape,
    };
}

fn validate_config(
    allocator: std.mem.Allocator,
    plan: *const marshal.SyncValuePlan,
    config: EmitConfig,
    memory_plan: *const marshal_ops.MemoryPlan,
) !void {
    if (config.memory_min_pages == 0) return error.InvalidMemorySize;
    if (plan.direction != config.direction) return error.DirectionMismatch;
    if (config.canonical_u64_arg != null and
        (config.direction != .lift or memory_plan.copy_shape != .list_elements or
            memory_plan.element_core_type != null))
    {
        return error.UnsupportedCanonicalExtraArgument;
    }
    for ([_][]const u8{
        config.function_name,
        config.export_name,
        config.input_local,
        config.realloc_name,
        config.canonical_call_name,
    }) |name| {
        if (!valid_wat_name(name)) return error.InvalidWatName;
    }
    if (!valid_import_text(config.canonical_import_module) or
        !valid_import_text(config.canonical_import_name))
    {
        return error.InvalidCanonicalImport;
    }

    const expected = try expected_canonical_import(allocator, plan.descriptor);
    defer allocator.free(expected.module);
    if (!std.mem.eql(u8, expected.module, config.canonical_import_module) or
        !std.mem.eql(u8, expected.name, config.canonical_import_name))
    {
        return error.CanonicalImportMismatch;
    }

    switch (config.direction) {
        .lower => {
            if (plan.abi.arguments.len != 1 or plan.abi.results.len != 0) return error.InvalidCanonicalArity;
        },
        .lift => {
            if (plan.abi.arguments.len != 0 or plan.abi.results.len != 1) return error.InvalidCanonicalArity;
        },
    }
}

pub const CanonicalImport = struct {
    module: []const u8,
    name: []const u8,
};

pub fn canonical_import_for_plan(
    allocator: std.mem.Allocator,
    descriptor: marshal.DescriptorIdentity,
) !CanonicalImport {
    return expected_canonical_import(allocator, descriptor);
}

fn expected_canonical_import(allocator: std.mem.Allocator, descriptor: marshal.DescriptorIdentity) !CanonicalImport {
    const package_at = std.mem.lastIndexOfScalar(u8, descriptor.package, '@') orelse return error.InvalidCanonicalImport;
    const member_dot = std.mem.indexOfScalar(u8, descriptor.member, '.') orelse return error.InvalidCanonicalImport;
    if (package_at == 0 or member_dot == 0 or member_dot + 1 >= descriptor.member.len) {
        return error.InvalidCanonicalImport;
    }
    if (std.mem.indexOfScalarPos(u8, descriptor.member, member_dot + 1, '.') != null) {
        return error.InvalidCanonicalImport;
    }

    return .{
        .module = try std.fmt.allocPrint(allocator, "{[package]s}/{[interface]s}{[suffix]s}", .{
            .package = descriptor.package[0..package_at],
            .interface = descriptor.member[0..member_dot],
            .suffix = descriptor.package[package_at..],
        }),
        .name = descriptor.member[member_dot + 1 ..],
    };
}

fn emit_canonical_import_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    direction: marshal.Direction,
    memory_plan: *const marshal_ops.MemoryPlan,
    plan: *const marshal.SyncValuePlan,
    config: EmitConfig,
) !void {
    if (memory_plan.copy_shape == .scalar) {
        const core_type = memory_plan.scalar_core_type orelse return error.MeasuredScalarCoreTypeMissing;
        const core_name = switch (core_type) {
            .i32 => "i32",
            .i64 => "i64",
            .f32 => "f32",
            .f64 => "f64",
        };
        switch (direction) {
            .lower => try generated_text.append_fmt(
                allocator,
                out,
                "  (type $canonical_lower (func (param {[core_name]s})))\n",
                .{ .core_name = core_name },
            ),
            .lift => try generated_text.append_fmt(
                allocator,
                out,
                "  (type $canonical_lift (func (result {[core_name]s})))\n",
                .{ .core_name = core_name },
            ),
        }
        return;
    }
    switch (memory_plan.copy_shape) {
        .record_fields => switch (direction) {
            .lower => try emit_record_lower_import_type(allocator, out, plan),
            .lift => try out.appendSlice(allocator, "  (type $canonical_lift (func (param i32)))\n"),
        },
        else => switch (direction) {
            .lower => try out.appendSlice(allocator, "  (type $canonical_lower (func (param i32 i32)))\n"),
            .lift => if (config.canonical_u64_arg != null)
                try out.appendSlice(allocator, "  (type $canonical_lift (func (param i64 i32)))\n")
            else
                try out.appendSlice(allocator, "  (type $canonical_lift (func (param i32)))\n"),
        },
    }
}

fn emit_record_lower_import_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
) !void {
    if (plan.root.measured.?.indirect != null) {
        try out.appendSlice(allocator, "  (type $canonical_lower (func (param i32)))\n");
        return;
    }
    try out.appendSlice(allocator, "  (type $canonical_lower (func (param");
    try append_record_lower_core_types(allocator, out, &plan.root);
    try out.appendSlice(allocator, ")))\n");
}

fn append_record_lower_core_types(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
) !void {
    if (node.kind != .record or node.children.len == 0) return error.UnsupportedMarshalShape;
    for (node.children) |*child| {
        switch (child.kind) {
            .scalar => {
                const facts = child.measured orelse return error.MeasuredChildMissing;
                const core_type = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
                const core_name = switch (core_type) {
                    .i32 => " i32",
                    .i64 => " i64",
                    .f32 => " f32",
                    .f64 => " f64",
                };
                try out.appendSlice(allocator, core_name);
            },
            .record => try append_record_lower_core_types(allocator, out, child),
            .text => try out.appendSlice(allocator, " i32 i32"),
            .list => try out.appendSlice(allocator, " i32 i32"),
            .map => return error.UnsupportedMarshalShape,
        }
    }
}

fn emit_record_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
) !void {
    if (plan.root.kind != .record or plan.root.children.len == 0) return error.UnsupportedMarshalShape;
    try emit_record_type_recursive(allocator, out, &plan.root, true);
}

fn emit_record_type_recursive(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
    is_root: bool,
) !void {
    if (node.kind != .record or node.children.len == 0) return error.UnsupportedMarshalShape;
    for (node.children) |*child| {
        if (child.kind == .record) {
            try emit_record_type_recursive(allocator, out, child, false);
        }
    }

    if (is_root) {
        try out.appendSlice(allocator, "  (type $do_record (struct");
    } else {
        const name = node.record_type_name orelse return error.UnsupportedMarshalShape;
        if (!valid_wat_name(name)) return error.InvalidWatName;
        try append_fmt(allocator, out, "  (type $do_{[name]s} (struct", .{ .name = name });
    }
    for (node.children, 0..) |*child, index| {
        switch (child.kind) {
            .scalar => {
                const facts = child.measured orelse return error.MeasuredChildMissing;
                const core_type = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
                const core_name = switch (core_type) {
                    .i32 => "i32",
                    .i64 => "i64",
                    .f32 => "f32",
                    .f64 => "f64",
                };
                try append_fmt(allocator, out, " (field $field{[index]d} {[core_name]s})", .{ .index = index, .core_name = core_name });
            },
            .record => {
                const name = child.record_type_name orelse return error.UnsupportedMarshalShape;
                if (!valid_wat_name(name)) return error.InvalidWatName;
                try append_fmt(allocator, out, " (field $field{[index]d} (ref null $do_{[name]s}))", .{ .index = index, .name = name });
            },
            .text => try append_fmt(allocator, out, " (field $field{[index]d} (ref null $do_text))", .{ .index = index }),
            .list => {
                const element = child.children[0];
                if (element.kind == .scalar and element.scalar_kind == .u32) {
                    try append_fmt(allocator, out, " (field $field{[index]d} (ref null $do_u32))", .{ .index = index });
                } else {
                    try append_fmt(allocator, out, " (field $field{[index]d} (ref null $do_bytes))", .{ .index = index });
                }
            },
            .map => return error.UnsupportedMarshalShape,
        }
    }
    try out.appendSlice(allocator, "))\n");
}

fn emit_realloc(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    emit_counters: bool,
) !void {
    const allocation_counter = if (emit_counters)
        \\      global.get $__alloc_count
        \\      i32.const 1
        \\      i32.add
        \\      global.set $__alloc_count
        \\
    else
        "";
    const free_counter = if (emit_counters)
        \\      global.get $__free_count
        \\      i32.const 1
        \\      i32.add
        \\      global.set $__free_count
        \\
    else
        "";
    try generated_text.append_fmt_block(
        allocator,
        out,
        2,
        \\  (func ${[name]s} (type $cabi_realloc_type)
        \\    (param $old i32)
        \\    (param $old_size i32)
        \\    (param $align i32)
        \\    (param $size i32)
        \\    (result i32)
        \\    (local $ptr i32)
        \\    local.get $old
        \\    i32.eqz
        \\    if (result i32)
        \\{[allocation_counter]s}      global.get $__marshal_heap
        \\      local.get $align
        \\      i32.const 1
        \\      i32.sub
        \\      i32.add
        \\      local.get $align
        \\      i32.const 1
        \\      i32.sub
        \\      i32.const -1
        \\      i32.xor
        \\      i32.and
        \\      local.tee $ptr
        \\      local.get $size
        \\      i32.add
        \\      global.set $__marshal_heap
        \\      local.get $ptr
        \\    else
        \\{[free_counter]s}      i32.const 0
        \\    end)
        \\  (export "cabi_realloc" (func ${[export_name]s}))
        \\
    , .{
        .name = name,
        .allocation_counter = allocation_counter,
        .free_counter = free_counter,
        .export_name = name,
    });
}

fn direction_name(direction: marshal.Direction) []const u8 {
    return switch (direction) {
        .lower => "lower",
        .lift => "lift",
    };
}

fn valid_wat_name(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.')) return false;
    }
    return true;
}

fn valid_import_text(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| {
        if (std.ascii.isControl(ch) or ch == '"' or ch == '\\') return false;
    }
    return true;
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime format: []const u8,
    args: anytype,
) !void {
    try generated_text.append_fmt(allocator, out, format, args);
}

test "marshal module wrapper rejects descriptor import drift" {
    var value = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    }, &value, .lower, .{ .layout = .{ .text = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectError(error.CanonicalImportMismatch, emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal/wrong@1.0.0",
        .canonical_import_name = "send",
    }));
}

test "marshal module wrapper can instrument realloc counters" {
    var value = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    }, &value, .lower, .{ .layout = .{ .text = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal/api@1.0.0",
        .canonical_import_name = "send",
        .emit_realloc_counters = true,
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(global $__alloc_count (mut i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(global $__free_count (mut i32)") != null);
}

test "marshal module wrapper accepts a measured u32 list shape" {
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:2222222222222222222222222222222222222222222222222222222222222222",
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
    } }, .children = &.{.{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } }} });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal/api@1.0.0",
        .canonical_import_name = "send",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u32") != null);
}

test "marshal module wrapper declares typed u32 list GC array" {
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:7777777777777777777777777777777777777777777777777777777777777777",
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

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal/api@1.0.0",
        .canonical_import_name = "send",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
}

test "marshal module wrapper uses an indirect result area for u32 list lift" {
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.receive",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    }, &value, .lift, .{ .layout = .{ .list = .{
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

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lift,
        .canonical_import_module = "demo:marshal/api@1.0.0",
        .canonical_import_name = "receive",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $__result_area") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 4") != null);
}

test "marshal module wrapper assembles scalar map lower and lift types" {
    var key = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer key.deinit();
    var value = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var map = try @import("wit_abi_types.zig").AbiType.map(std.testing.allocator, &key, &value);
    defer map.deinit();

    const lower_plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-map@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    }, &map, .lower, .{
        .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 8,
            .element_stride = 8,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 4, .alignment = 4 },
            .capacity = 4,
            .accepted_lengths = &.{ 0, 1, 4 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, lower_plan);
    const lower_wat = try emit_sync_marshal_module(std.testing.allocator, &lower_plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-map/api@1.0.0",
        .canonical_import_name = "lookup",
    });
    defer std.testing.allocator.free(lower_wat);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "(type $do_map") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "(type $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "(param $input (ref null $do_map))") != null);

    const lift_plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-map@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    }, &map, .lift, .{
        .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 8,
            .element_stride = 8,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 4, .alignment = 4 },
            .capacity = 4,
            .accepted_lengths = &.{ 0, 1, 4 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, lift_plan);
    const lift_wat = try emit_sync_marshal_module(std.testing.allocator, &lift_plan, .{
        .direction = .lift,
        .canonical_import_module = "demo:marshal-map/api@1.0.0",
        .canonical_import_name = "lookup",
    });
    defer std.testing.allocator.free(lift_wat);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "(type $do_map") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "(result (ref null $do_map))") != null);
}

test "marshal module wrapper declares scalar record lift type" {
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

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lift,
        .canonical_import_module = "demo:marshal-record/api@1.0.0",
        .canonical_import_name = "read",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_record (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $cabi_realloc") == null);
}

test "marshal module wrapper declares scalar record lower flat type" {
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

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record/api@1.0.0",
        .canonical_import_name = "write",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record/api@1.0.0\" \"write\" (func $canonical_call (type $canonical_lower)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $marshal (param $input (ref null $do_record))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"marshal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory ") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "cabi_realloc") == null);
}

test "marshal module wrapper declares bounded record byte-list lower ABI" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var byte = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer byte.deinit();
    var payload = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &byte);
    defer payload.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "payload", .value = &payload },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-byte-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:byte-list-record-lower-v1",
    }, &value, .lower, .{
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

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-byte-list-lower/api@1.0.0",
        .canonical_import_name = "write",
        .emit_realloc_counters = true,
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-byte-list-lower/api@1.0.0\" \"write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $cabi_realloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(global $__alloc_count (mut i32)") != null);
}

test "marshal module wrapper declares mixed scalar-list lower linear support" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer element.deinit();
    var payload = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer payload.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "payload", .value = &payload },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-mixed-scalar-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-scalar-list-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "payload", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
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
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0",
        .canonical_import_name = "write",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $cabi_realloc") != null);
}

test "marshal module wrapper declares bounded record u32-list lower ABI" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var payload = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer payload.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "payload", .value = &payload },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-u32-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:u32-list-record-lower-v1",
    }, &value, .lower, .{
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
            .{
                .layout = .{ .list = .{
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
                } },
                .children = &.{.{ .layout = .{ .scalar = .{
                    .offset = 0,
                    .byte_size = 4,
                    .alignment = 4,
                    .core_type = .i32,
                } } }},
            },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-u32-list-lower/api@1.0.0",
        .canonical_import_name = "write",
        .emit_realloc_counters = true,
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_record (struct (field $field0 i32) (field $field1 (ref null $do_u32))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.store") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "global.get $__marshal_heap\n" ++
        "      local.get $align\n" ++
        "      i32.const 1\n" ++
        "      i32.sub\n" ++
        "      i32.add\n" ++
        "      local.get $align\n" ++
        "      i32.const 1\n" ++
        "      i32.sub\n" ++
        "      i32.const -1\n" ++
        "      i32.xor\n" ++
        "      i32.and\n" ++
        "      local.tee $ptr\n" ++
        "      local.get $size\n" ++
        "      i32.add\n" ++
        "      global.set $__marshal_heap\n" ++
        "      local.get $ptr") != null);
}

test "marshal module wrapper declares bounded record two u32-list lower support" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var first_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer first_element.deinit();
    var first = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &first_element);
    defer first.deinit();
    var second_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer second_element.deinit();
    var second = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &second_element);
    defer second.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "first", .value = &first },
        .{ .name = "second", .value = &second },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-two-u32-lists-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:two-u32-list-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "first", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "second", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
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
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-two-u32-lists-lower/api@1.0.0",
        .canonical_import_name = "write",
        .emit_realloc_counters = true,
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $cabi_realloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-two-u32-lists-lower/api@1.0.0\" \"write\"") != null);

    var support = std.ArrayList(u8).empty;
    defer support.deinit(std.testing.allocator);
    try emit_sync_marshal_gc_support(std.testing.allocator, &support, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-two-u32-lists-lower/api@1.0.0",
        .canonical_import_name = "write",
    });
    try std.testing.expect(std.mem.indexOf(u8, support.items, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, support.items, "(func $cabi_realloc") != null);
}

test "marshal module wrapper declares bounded record text and two u32-list lower support" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var first_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer first_element.deinit();
    var first = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &first_element);
    defer first.deinit();
    var second_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer second_element.deinit();
    var second = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &second_element);
    defer second.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "first", .value = &first },
        .{ .name = "second", .value = &second },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-mixed-text-two-u32-lists-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-text-two-u32-lists-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 28,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "first", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "second", .offset = 20, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
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
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0",
        .canonical_import_name = "write",
        .emit_realloc_counters = true,
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0\" \"write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "block $__text_two_lists_cleanup") != null);
}

test "marshal module wrapper declares bounded record text byte/u32-list lower support" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var byte_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer byte_element.deinit();
    var bytes = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &byte_element);
    defer bytes.deinit();
    var value_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer value_element.deinit();
    var values = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &value_element);
    defer values.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "bytes", .value = &bytes },
        .{ .name = "values", .value = &values },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-mixed-text-byte-u32-lists-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-text-byte-u32-lists-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 28,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "bytes", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "values", .offset = 20, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
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
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0",
        .canonical_import_name = "write",
        .emit_realloc_counters = true,
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $cabi_realloc") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "array.get $do_u32"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32 i32 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0\" \"write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "block $__text_two_lists_cleanup") != null);

    var support = std.ArrayList(u8).empty;
    defer support.deinit(std.testing.allocator);
    try emit_sync_marshal_gc_support(std.testing.allocator, &support, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0",
        .canonical_import_name = "write",
    });
    try std.testing.expect(std.mem.indexOf(u8, support.items, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, support.items, "(func $cabi_realloc") != null);
}

test "marshal module wrapper rejects GC references at the canonical boundary" {
    var value = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer value.deinit();
    var plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    }, &value, .lower, .{ .layout = .{ .text = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);
    plan.root.contains_gc_reference = true;

    try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lower,
        .canonical_import_module = "demo:marshal/api@1.0.0",
        .canonical_import_name = "send",
    }));
}

test "WASI random list<u8> canonical import keeps the versioned WIT identity" {
    const canonical = try canonical_import_for_plan(std.testing.allocator, .{
        .package = "wasi:random@0.3.0-rc-2025-09-16",
        .world = "imports",
        .member = "random.get-random-bytes",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    });
    defer std.testing.allocator.free(canonical.module);

    try std.testing.expectEqualStrings("wasi:random/random@0.3.0-rc-2025-09-16", canonical.module);
    try std.testing.expectEqualStrings("get-random-bytes", canonical.name);
}

test "WASI random list<u8> lift passes a bounded u64 length to the canonical import" {
    var byte = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer byte.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &byte);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "wasi:random@0.3.0-rc-2025-09-16",
        .world = "imports",
        .member = "random.get-random-bytes",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    }, &value, .lift, .{ .layout = .{ .byte_list = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 1,
        .element_stride = 1,
        .element_alignment = 1,
        .capacity = 16,
        .accepted_lengths = &.{ 0, 1, 16 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } } });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_module(std.testing.allocator, &plan, .{
        .direction = .lift,
        .canonical_import_module = "wasi:random/random@0.3.0-rc-2025-09-16",
        .canonical_import_name = "get-random-bytes",
        .canonical_u64_arg = 16,
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i64 i32)))") != null);
    const arg = std.mem.indexOf(u8, wat, "i64.const 16") orelse return error.TestExpectedEqual;
    const result_area = std.mem.indexOf(u8, wat, "local.get $__result_area") orelse return error.TestExpectedEqual;
    try std.testing.expect(arg < result_area);
}
