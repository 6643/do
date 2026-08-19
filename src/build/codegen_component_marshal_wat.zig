//! Bounded synchronous WAT emission for measured text and byte-list plans.
//!
//! This module emits a core-module fragment only. It does not admit the
//! host/WIT route by itself; callers must still provide the pinned descriptor
//! and keep component assembly behind the G5c gate.
const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const marshal_ops = @import("codegen_component_marshal_ops.zig");
const wit_layout = @import("wit_abi_layout.zig");

pub const EmitConfig = struct {
    function_name: []const u8 = "marshal",
    input_local: []const u8 = "input",
    realloc_name: []const u8 = "cabi_realloc",
    canonical_call_name: []const u8 = "canonical_call",
    canonical_u64_arg: ?u64 = null,
};

pub fn emit_sync_marshal_function(
    allocator: std.mem.Allocator,
    plan: *const marshal.SyncValuePlan,
    config: EmitConfig,
) ![]u8 {
    try validate_config(config);
    const memory_plan = try marshal_ops.build_sync_memory_plan(plan);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    switch (memory_plan.copy_shape) {
        .scalar => try emit_scalar(allocator, &out, memory_plan.direction, memory_plan.scalar_core_type orelse return error.MeasuredScalarCoreTypeMissing, config),
        .text_bytes, .list_elements => switch (memory_plan.direction) {
            .lower => try emit_lower(allocator, &out, &memory_plan, config),
            .lift => try emit_lift(allocator, &out, &memory_plan, config),
        },
        .record_fields => switch (memory_plan.direction) {
            .lower => try emit_record_lower(allocator, &out, plan, &memory_plan, config),
            .lift => try emit_record_lift(allocator, &out, plan, &memory_plan, config),
        },
    }
    return out.toOwnedSlice(allocator);
}

fn emit_scalar(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    direction: marshal.Direction,
    core_type: wit_layout.CoreWord,
    config: EmitConfig,
) !void {
    const core_name = switch (core_type) {
        .i32 => "i32",
        .i64 => "i64",
        .f32 => "f32",
        .f64 => "f64",
    };
    switch (direction) {
        .lower => try append_fmt(allocator, out, "  (func ${s} (param ${s} {s})\n" ++
            "    local.get ${s}\n" ++
            "    call ${s})\n", .{ config.function_name, config.input_local, core_name, config.input_local, config.canonical_call_name }),
        .lift => try append_fmt(allocator, out, "  (func ${s} (result {s})\n" ++
            "    call ${s})\n", .{ config.function_name, core_name, config.canonical_call_name }),
    }
}

fn validate_config(config: EmitConfig) !void {
    if (!valid_wat_name(config.function_name) or
        !valid_wat_name(config.input_local) or
        !valid_wat_name(config.realloc_name) or
        !valid_wat_name(config.canonical_call_name))
    {
        return error.InvalidWatName;
    }
}

fn valid_wat_name(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.')) return false;
    }
    return true;
}

fn emit_lower(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const source_type = switch (memory_plan.copy_shape) {
        .scalar => return error.UnsupportedMarshalShape,
        .text_bytes => "(ref null $do_text)",
        .list_elements => if (memory_plan.element_core_type != null) "(ref null $do_u32)" else "(ref null $do_bytes)",
        .record_fields => return error.UnsupportedMarshalShape,
    };
    try append_fmt(allocator, out, "  (func ${s} (param ${s} {s})\n" ++
        "    (local $__gc_length i32)\n" ++
        "    (local $__gc_index i32)\n" ++
        "    (local $__copy_bytes i32)\n" ++
        "    (local $__copy_bytes64 i64)\n" ++
        "    (local $__cabi_ptr i32)\n" ++
        "    (local $__memory_bytes i64)\n", .{ config.function_name, config.input_local, source_type });

    try append_source_length(allocator, out, memory_plan.copy_shape, config.input_local);
    try append_copy_byte_count(allocator, out, memory_plan.element_stride);
    try append_source_length_guard(allocator, out, memory_plan.copy_shape, config.input_local);
    try out.appendSlice(allocator, "    i32.const 0\n" ++
        "    i32.const 0\n" ++
        "    i32.const ");
    try append_fmt(allocator, out, "{d}\n    local.get $__copy_bytes\n", .{memory_plan.element_stride});
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");
    try out.appendSlice(allocator, "    i32.const 0\n" ++
        "    local.set $__gc_index\n" ++
        "    block $__copy_done\n" ++
        "      loop $__copy\n" ++
        "        local.get $__gc_index\n" ++
        "        local.get $__gc_length\n" ++
        "        i32.ge_u\n" ++
        "        br_if $__copy_done\n" ++
        "        local.get $__cabi_ptr\n" ++
        "        local.get $__gc_index\n");
    if (memory_plan.element_stride != 1) {
        try append_fmt(allocator, out, "        i32.const {d}\n        i32.mul\n", .{memory_plan.element_stride});
    }
    try out.appendSlice(allocator, "        i32.add\n");
    try append_source_element(allocator, out, memory_plan, config.input_local);
    if (memory_plan.element_stride == 1) {
        try out.appendSlice(allocator, "        i32.store8\n");
    } else {
        try out.appendSlice(allocator, "        i32.store\n");
    }
    try out.appendSlice(allocator, "        local.get $__gc_index\n" ++
        "        i32.const 1\n" ++
        "        i32.add\n" ++
        "        local.set $__gc_index\n" ++
        "        br $__copy\n" ++
        "      end\n" ++
        "    end\n" ++
        "    local.get $__cabi_ptr\n" ++
        "    local.get $__gc_length\n");
    try append_named_call(allocator, out, config.canonical_call_name);
    try out.appendSlice(allocator, "    local.get $__cabi_ptr\n" ++
        "    local.get $__copy_bytes\n" ++
        "    i32.const ");
    try append_fmt(allocator, out, "{d}\n", .{memory_plan.element_stride});
    try out.appendSlice(allocator, "    i32.const 0\n");
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    drop)\n");
}

fn emit_lift(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const result_area_pointer_offset = memory_plan.result_area_pointer_offset orelse return error.MeasuredResultAreaPointerMissing;
    const result_area_length_offset = memory_plan.result_area_length_offset orelse return error.MeasuredResultAreaLengthMissing;
    const result_type = switch (memory_plan.copy_shape) {
        .scalar => return error.UnsupportedMarshalShape,
        .text_bytes => "(ref null $do_text)",
        .list_elements => if (memory_plan.element_core_type != null) "(ref null $do_u32)" else "(ref null $do_bytes)",
        .record_fields => return error.UnsupportedMarshalShape,
    };
    const array_type = if (memory_plan.element_core_type != null) "$do_u32" else "$do_bytes";
    try append_fmt(allocator, out, "  (func ${s} (result {s})\n" ++
        "    (local $__cabi_ptr i32)\n" ++
        "    (local $__result_area i32)\n" ++
        "    (local $__gc_length i32)\n" ++
        "    (local $__gc_index i32)\n" ++
        "    (local $__copy_bytes i32)\n" ++
        "    (local $__copy_bytes64 i64)\n" ++
        "    (local $__memory_bytes i64)\n" ++
        "    (local $__gc_bytes (ref {s}))\n" ++
        "    (local $__gc_result {s})\n", .{ config.function_name, result_type, array_type, result_type });
    // Canonical list/text results write `(ptr, len)` into the measured result area.
    try out.appendSlice(allocator, "    i32.const 0\n    local.set $__result_area\n");
    if (config.canonical_u64_arg) |arg| {
        try append_fmt(allocator, out, "    i64.const {d}\n", .{arg});
    }
    try out.appendSlice(allocator, "    local.get $__result_area\n");
    try append_named_call(allocator, out, config.canonical_call_name);
    try append_fmt(allocator, out, "    local.get $__result_area\n    i32.const {d}\n    i32.add\n    i32.load\n    local.set $__cabi_ptr\n" ++
        "    local.get $__result_area\n    i32.const {d}\n    i32.add\n    i32.load\n    local.set $__gc_length\n", .{ result_area_pointer_offset, result_area_length_offset });
    try append_copy_byte_count(allocator, out, memory_plan.element_stride);
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");
    try out.appendSlice(allocator, "    local.get $__gc_length\n" ++
        "    array.new_default ");
    try out.appendSlice(allocator, array_type);
    try out.appendSlice(allocator, "\n" ++
        "    local.set $__gc_bytes\n" ++
        "    i32.const 0\n" ++
        "    local.set $__gc_index\n" ++
        "    block $__copy_done\n" ++
        "      loop $__copy\n" ++
        "        local.get $__gc_index\n" ++
        "        local.get $__gc_length\n" ++
        "        i32.ge_u\n" ++
        "        br_if $__copy_done\n" ++
        "        local.get $__gc_bytes\n" ++
        "        local.get $__gc_index\n" ++
        "        local.get $__cabi_ptr\n" ++
        "        local.get $__gc_index\n");
    if (memory_plan.element_stride != 1) {
        try append_fmt(allocator, out, "        i32.const {d}\n        i32.mul\n", .{memory_plan.element_stride});
    }
    try out.appendSlice(allocator, "        i32.add\n");
    if (memory_plan.element_stride == 1) {
        try out.appendSlice(allocator, "        i32.load8_u\n");
    } else {
        try out.appendSlice(allocator, "        i32.load\n");
    }
    try append_fmt(allocator, out, "        array.set {s}\n", .{array_type});
    try out.appendSlice(allocator, "        local.get $__gc_index\n" ++
        "        i32.const 1\n" ++
        "        i32.add\n" ++
        "        local.set $__gc_index\n" ++
        "        br $__copy\n" ++
        "      end\n" ++
        "    end\n");
    switch (memory_plan.copy_shape) {
        .scalar => return error.UnsupportedMarshalShape,
        .text_bytes => try out.appendSlice(allocator, "    local.get $__gc_length\n" ++
            "    local.get $__gc_bytes\n" ++
            "    struct.new $do_text\n" ++
            "    local.set $__gc_result\n"),
        .list_elements => try out.appendSlice(allocator, "    local.get $__gc_bytes\n    local.set $__gc_result\n"),
        .record_fields => return error.UnsupportedMarshalShape,
    }
    try out.appendSlice(allocator, "    local.get $__cabi_ptr\n" ++
        "    local.get $__copy_bytes\n" ++
        "    i32.const ");
    try append_fmt(allocator, out, "{d}\n", .{memory_plan.element_stride});
    try out.appendSlice(allocator, "    i32.const 0\n");
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    drop\n    local.get $__gc_result)\n");
}

fn emit_record_lift(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const measured = plan.root.measured orelse return error.MeasuredLayoutRequired;
    if (plan.root.kind != .record or plan.root.children.len != memory_plan.record_field_count) {
        return error.UnsupportedMarshalShape;
    }
    if (measured.byte_size == 0) return error.UnsupportedMarshalShape;

    try append_fmt(allocator, out, "  (func ${s} (result (ref null $do_record))\n" ++
        "    (local $__result_area i32)\n" ++
        "    (local $__record_bytes i32)\n" ++
        "    (local $__memory_bytes i64)\n" ++
        "    i32.const 0\n" ++
        "    local.set $__result_area\n" ++
        "    local.get $__result_area\n", .{config.function_name});
    try append_named_call(allocator, out, config.canonical_call_name);
    try append_fmt(allocator, out, "    i32.const {d}\n" ++
        "    local.set $__record_bytes\n", .{measured.byte_size});
    try emit_span_guard(allocator, out, "__result_area", "__record_bytes");

    for (plan.root.children) |*child| {
        if (child.kind != .scalar) return error.UnsupportedMarshalShape;
        const child_facts = child.measured orelse return error.MeasuredChildMissing;
        const core_type = child_facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
        const load_name = switch (core_type) {
            .i32 => "i32.load",
            .i64 => "i64.load",
            .f32 => "f32.load",
            .f64 => "f64.load",
        };
        try append_fmt(allocator, out, "    local.get $__result_area\n" ++
            "    i32.const {d}\n" ++
            "    i32.add\n" ++
            "    {s}\n", .{ child_facts.offset, load_name });
    }
    try out.appendSlice(allocator, "    struct.new $do_record)\n");
}

fn emit_record_lower(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const measured = plan.root.measured orelse return error.MeasuredLayoutRequired;
    if (plan.root.kind != .record or plan.root.children.len != memory_plan.record_field_count) {
        return error.UnsupportedMarshalShape;
    }
    if (measured.byte_size == 0 or measured.alignment == 0) return error.UnsupportedMarshalShape;

    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null $do_record))\n", .{ config.function_name, config.input_local });

    if (memory_plan.record_indirect != null) {
        try out.appendSlice(allocator,
            "    (local $__cabi_ptr i32)\n" ++
                "    (local $__record_bytes i32)\n" ++
                "    (local $__memory_bytes i64)\n" ++
                "    i32.const 0\n" ++
                "    i32.const 0\n");
        try append_fmt(allocator, out, "    i32.const {d}\n    i32.const {d}\n", .{ measured.alignment, measured.byte_size });
        try append_named_call(allocator, out, config.realloc_name);
        try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
        try out.appendSlice(allocator, "    i32.const ");
        try append_fmt(allocator, out, "{d}\n    local.set $__record_bytes\n", .{measured.byte_size});
        try emit_span_guard(allocator, out, "__cabi_ptr", "__record_bytes");

        for (plan.root.children, 0..) |*child, index| {
            if (child.kind != .scalar) return error.UnsupportedMarshalShape;
            const child_facts = child.measured orelse return error.MeasuredChildMissing;
            const core_type = child_facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
            const store_name = switch (core_type) {
                .i32 => "i32.store",
                .i64 => "i64.store",
                .f32 => "f32.store",
                .f64 => "f64.store",
            };
            const store_offset = if (child_facts.offset == 0)
                try allocator.dupe(u8, store_name)
            else
                try std.fmt.allocPrint(allocator, "{s} offset={d}", .{ store_name, child_facts.offset });
            defer allocator.free(store_offset);
            try append_fmt(allocator, out, "    local.get $__cabi_ptr\n" ++
                "    local.get ${s}\n" ++
                "    ref.as_non_null\n" ++
                "    struct.get $do_record $field{d}\n" ++
                "    {s}\n", .{ config.input_local, index, store_offset });
        }

        try out.appendSlice(allocator, "    local.get $__cabi_ptr\n");
        try append_named_call(allocator, out, config.canonical_call_name);
        try out.appendSlice(allocator, "    local.get $__cabi_ptr\n");
        try append_fmt(allocator, out, "    i32.const {d}\n    i32.const {d}\n    i32.const 0\n", .{ measured.byte_size, measured.alignment });
        try append_named_call(allocator, out, config.realloc_name);
        try out.appendSlice(allocator, "    drop)\n");
        return;
    }

    for (plan.root.children, 0..) |*child, index| {
        if (child.kind != .scalar) return error.UnsupportedMarshalShape;
        const child_facts = child.measured orelse return error.MeasuredChildMissing;
        const core_type = child_facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
        _ = switch (core_type) {
            .i32 => "i32",
            .i64 => "i64",
            .f32 => "f32",
            .f64 => "f64",
        };
        try append_fmt(allocator, out, "    local.get ${s}\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_record $field{d}\n" ++
            "", .{ config.input_local, index });
    }

    try append_named_call(allocator, out, config.canonical_call_name);
    try out.appendSlice(allocator, ")\n");
}

fn append_source_length(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    copy_shape: marshal_ops.CopyShape,
    input_local: []const u8,
) !void {
    switch (copy_shape) {
        .scalar => return error.UnsupportedMarshalShape,
        .text_bytes => try append_fmt(allocator, out, "    local.get ${s}\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_text $length\n" ++
            "    local.set $__gc_length\n", .{input_local}),
        .list_elements => try append_fmt(allocator, out, "    local.get ${s}\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    local.set $__gc_length\n", .{input_local}),
        .record_fields => return error.UnsupportedMarshalShape,
    }
}

fn append_source_length_guard(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    copy_shape: marshal_ops.CopyShape,
    input_local: []const u8,
) !void {
    if (copy_shape != .text_bytes) return;
    try append_fmt(allocator, out, "    local.get $__gc_length\n" ++
        "    local.get ${s}\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.gt_u\n" ++
        "    if unreachable end\n", .{input_local});
}

fn append_source_byte(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    copy_shape: marshal_ops.CopyShape,
    input_local: []const u8,
) !void {
    switch (copy_shape) {
        .scalar => return error.UnsupportedMarshalShape,
        .text_bytes => try append_fmt(allocator, out, "        local.get ${s}\n" ++
            "        ref.as_non_null\n" ++
            "        struct.get $do_text $bytes\n" ++
            "        ref.as_non_null\n" ++
            "        local.get $__gc_index\n" ++
            "        array.get_s $do_bytes\n", .{input_local}),
        .list_elements => try append_fmt(allocator, out, "        local.get ${s}\n" ++
            "        ref.as_non_null\n" ++
            "        local.get $__gc_index\n" ++
            "        array.get_s $do_bytes\n", .{input_local}),
        .record_fields => return error.UnsupportedMarshalShape,
    }
}

fn append_source_element(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    memory_plan: *const marshal_ops.MemoryPlan,
    input_local: []const u8,
) !void {
    if (memory_plan.copy_shape == .text_bytes) {
        try append_source_byte(allocator, out, .text_bytes, input_local);
        return;
    }
    if (memory_plan.element_core_type != null) {
        try append_fmt(allocator, out, "        local.get ${s}\n" ++
            "        ref.as_non_null\n" ++
            "        local.get $__gc_index\n" ++
            "        array.get $do_u32\n", .{input_local});
        return;
    }
    try append_source_byte(allocator, out, .list_elements, input_local);
}

fn append_copy_byte_count(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    stride: u32,
) !void {
    if (stride == 0) return error.InvalidCopyStride;
    if (stride == 1) {
        try out.appendSlice(allocator, "    local.get $__gc_length\n    local.set $__copy_bytes\n");
        return;
    }
    try append_fmt(allocator, out, "    local.get $__gc_length\n" ++
        "    i64.extend_i32_u\n" ++
        "    i64.const {d}\n" ++
        "    i64.mul\n" ++
        "    local.tee $__copy_bytes64\n" ++
        "    i64.const 4294967295\n" ++
        "    i64.gt_u\n" ++
        "    if unreachable end\n" ++
        "    local.get $__copy_bytes64\n" ++
        "    i32.wrap_i64\n" ++
        "    local.set $__copy_bytes\n", .{stride});
}

fn append_named_call(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try append_fmt(allocator, out, "    call ${s}\n", .{name});
}

fn emit_span_guard(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    pointer_local: []const u8,
    length_local: []const u8,
) !void {
    try append_fmt(allocator, out, "    memory.size\n" ++
        "    i64.extend_i32_u\n" ++
        "    i64.const 65536\n" ++
        "    i64.mul\n" ++
        "    local.set $__memory_bytes\n" ++
        "    local.get ${s}\n" ++
        "    i64.extend_i32_u\n" ++
        "    local.get $__memory_bytes\n" ++
        "    i64.gt_u\n" ++
        "    if unreachable end\n" ++
        "    local.get ${s}\n" ++
        "    i64.extend_i32_u\n" ++
        "    local.get $__memory_bytes\n" ++
        "    local.get ${s}\n" ++
        "    i64.extend_i32_u\n" ++
        "    i64.sub\n" ++
        "    i64.gt_u\n" ++
        "    if unreachable end\n", .{ pointer_local, length_local, pointer_local });
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime format: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

test "canonical marshal WAT lower emits checked text copy and call order" {
    var value = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .realloc_name = "alloc",
        .canonical_call_name = "host_call",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "memory.size") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.mul") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $alloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.store8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $host_call") != null);
    try std.testing.expect((std.mem.indexOf(u8, wat, "i32.store8") orelse unreachable) <
        (std.mem.indexOf(u8, wat, "call $host_call") orelse unreachable));
}

test "canonical marshal WAT lift emits checked load construct publish and free order" {
    var byte = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer byte.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &byte);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "receive",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:receive-bytes-v1",
    }, &value, .lift, .{
        .layout = .{ .byte_list = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 1,
            .element_stride = 1,
            .element_alignment = 1,
            .capacity = 16,
            .accepted_lengths = &.{ 0, 1, 2, 4, 8, 16 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{});
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load8_u") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $__gc_result") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $cabi_realloc") != null);
    try std.testing.expect((std.mem.indexOf(u8, wat, "array.set $do_bytes") orelse unreachable) <
        (std.mem.lastIndexOf(u8, wat, "call $cabi_realloc") orelse unreachable));
}

test "canonical marshal WAT emits typed u32 list lower and lift copies" {
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer value.deinit();
    const lower_plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:5555555555555555555555555555555555555555555555555555555555555555",
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
    defer marshal.deinit_sync_value_plan(std.testing.allocator, lower_plan);
    const lower_wat = try emit_sync_marshal_function(std.testing.allocator, &lower_plan, .{});
    defer std.testing.allocator.free(lower_wat);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "(ref null $do_u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "array.get $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "i32.store") != null);

    const lift_plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.receive",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:6666666666666666666666666666666666666666666666666666666666666666",
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
    defer marshal.deinit_sync_value_plan(std.testing.allocator, lift_plan);
    const lift_wat = try emit_sync_marshal_function(std.testing.allocator, &lift_plan, .{});
    defer std.testing.allocator.free(lift_wat);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "(ref null $do_u32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "array.set $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "i32.load") != null);
}

test "canonical marshal WAT lifts a scalar record from the result area" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{});
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_record))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $cabi_realloc") == null);
}

test "canonical marshal WAT lowers a scalar record by flattening fields" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{});
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $do_record))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.store") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $cabi_realloc") == null);
}

test "canonical marshal WAT keeps unsupported shapes rejected" {
    var left = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer left.deinit();
    var right = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer right.deinit();
    var tuple = try @import("wit_abi_types.zig").AbiType.tuple(std.testing.allocator, &.{ &left, &right });
    defer tuple.deinit();
    try std.testing.expectError(error.UnsupportedMarshalShape, marshal.build_sync_value_plan(std.testing.allocator, .{
        .package = "example:host@0.1.0",
        .world = "host",
        .member = "tuple",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:tuple-v1",
    }, &tuple, .lower));
}
