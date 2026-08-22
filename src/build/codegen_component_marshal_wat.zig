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
    /// Source-level root record name used by the surrounding GC module.
    /// Standalone marshal probes keep their historical `do_record` default.
    root_type_name: []const u8 = "do_record",
};

const RecordPathSegment = struct {
    type_name: []const u8,
    is_root: bool,
    field_index: usize,
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

/// Return the scalar leaf count for a measured record whose entire tree is
/// scalar/record-only. This is the compiler-facing bridge shape used by the
/// bounded ordinary GC host route; it deliberately rejects text, lists, and
/// unmeasured nodes.
pub fn sync_scalar_record_leaf_count(plan: *const marshal.SyncValuePlan) !usize {
    if (plan.root.kind != .record or plan.root.children.len == 0) return error.UnsupportedMarshalShape;
    return scalar_record_leaf_count_node(&plan.root);
}

fn scalar_record_leaf_count_node(node: *const marshal.MarshalNode) !usize {
    switch (node.kind) {
        .scalar => {
            const facts = node.measured orelse return error.MeasuredChildMissing;
            _ = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
            return 1;
        },
        .record => {
            _ = node.measured orelse return error.MeasuredNodeMissing;
            if (node.children.len == 0) return error.UnsupportedMarshalShape;
            var count: usize = 0;
            for (node.children) |*child| {
                count = std.math.add(usize, count, try scalar_record_leaf_count_node(child)) catch return error.OffsetOverflow;
            }
            return count;
        },
        else => return error.UnsupportedMarshalShape,
    }
}

/// Emit the compiler-facing wrapper for a pure scalar nested record. The WIT
/// canonical import remains memory-based (lift result area) or flattened
/// scalar (lower); this wrapper only translates between that boundary and the
/// ordinary GC compiler's inline scalar-record ABI.
pub fn emit_sync_scalar_record_bridge_function(
    allocator: std.mem.Allocator,
    plan: *const marshal.SyncValuePlan,
    config: EmitConfig,
) ![]u8 {
    try validate_config(config);
    try marshal.validate_sync_value_plan(plan);
    const leaf_count = try sync_scalar_record_leaf_count(plan);
    const measured = plan.root.measured orelse return error.MeasuredNodeMissing;
    if (measured.byte_size == 0 or measured.alignment == 0) return error.UnsupportedMarshalShape;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    switch (plan.direction) {
        .lower => {
            if (plan.abi.arguments.len != 1 or plan.abi.results.len != 0) return error.InvalidCanonicalArity;
            try append_fmt(allocator, &out, "  (func ${s}", .{config.function_name});
            _ = try append_scalar_record_param_types(allocator, &out, &plan.root, 0);
            try out.appendSlice(allocator, "\n");
            for (0..leaf_count) |index| {
                try append_fmt(allocator, &out, "    local.get $__gc_arg_{d}\n", .{index});
            }
            try append_fmt(allocator, &out, "    call ${s})\n", .{config.canonical_call_name});
        },
        .lift => {
            if (plan.abi.arguments.len != 0 or plan.abi.results.len != 1) return error.InvalidCanonicalArity;
            try append_fmt(allocator, &out, "  (func ${s} (result", .{config.function_name});
            try append_scalar_record_result_types(allocator, &out, &plan.root);
            try out.appendSlice(allocator, ")\n" ++
                "    (local $__result_area i32)\n" ++
                "    i32.const 0\n" ++
                "    local.set $__result_area\n");
            try append_fmt(allocator, &out, "    local.get $__result_area\n    call ${s}\n", .{config.canonical_call_name});
            try emit_scalar_record_loads(allocator, &out, &plan.root, 0, true);
            try out.appendSlice(allocator, "  )\n");
        },
    }
    return out.toOwnedSlice(allocator);
}

fn append_scalar_record_param_types(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
    index: usize,
) !usize {
    switch (node.kind) {
        .scalar => {
            const facts = node.measured orelse return error.MeasuredChildMissing;
            const core_type = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
            try append_fmt(allocator, out, " (param $__gc_arg_{d} {s})", .{ index, core_type_name(core_type) });
            return index + 1;
        },
        .record => {
            var next = index;
            for (node.children) |*child| next = try append_scalar_record_param_types(allocator, out, child, next);
            return next;
        },
        else => return error.UnsupportedMarshalShape,
    }
}

fn append_scalar_record_result_types(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
) !void {
    switch (node.kind) {
        .scalar => {
            const facts = node.measured orelse return error.MeasuredChildMissing;
            const core_type = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
            try append_fmt(allocator, out, " {s}", .{core_type_name(core_type)});
        },
        .record => for (node.children) |*child| try append_scalar_record_result_types(allocator, out, child),
        else => return error.UnsupportedMarshalShape,
    }
}

fn emit_scalar_record_loads(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
    base_offset: u32,
    is_root: bool,
) !void {
    switch (node.kind) {
        .scalar => {
            const facts = node.measured orelse return error.MeasuredChildMissing;
            const core_type = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
            const offset = std.math.add(u32, base_offset, facts.offset) catch return error.OffsetOverflow;
            try append_fmt(allocator, out, "    local.get $__result_area\n" ++
                "    i32.const {d}\n" ++
                "    i32.add\n" ++
                "    {s}\n", .{ offset, scalar_load_name(core_type) });
        },
        .record => {
            const facts = node.measured orelse return error.MeasuredNodeMissing;
            const record_offset = if (is_root)
                base_offset
            else
                std.math.add(u32, base_offset, facts.offset) catch return error.OffsetOverflow;
            for (node.children) |*child| try emit_scalar_record_loads(allocator, out, child, record_offset, false);
        },
        else => return error.UnsupportedMarshalShape,
    }
}

fn core_type_name(core_type: wit_layout.CoreWord) []const u8 {
    return switch (core_type) {
        .i32 => "i32",
        .i64 => "i64",
        .f32 => "f32",
        .f64 => "f64",
    };
}

fn scalar_load_name(core_type: wit_layout.CoreWord) []const u8 {
    return switch (core_type) {
        .i32 => "i32.load",
        .i64 => "i64.load",
        .f32 => "f32.load",
        .f64 => "f64.load",
    };
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
        !valid_wat_name(config.canonical_call_name) or
        !valid_wat_name(config.root_type_name))
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

fn append_lowercase_wat_name(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try out.append(allocator, '$');
    for (name) |ch| try out.append(allocator, std.ascii.toLower(ch));
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

    const has_record_list = marshal_ops.record_contains_list(&plan.root);
    const has_record_u32_list = marshal_ops.record_contains_u32_list(&plan.root);
    const has_record_byte_list = marshal_ops.record_contains_byte_list(&plan.root);
    try append_fmt(allocator, out, "  (func ${s} (result (ref null ", .{config.function_name});
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try out.appendSlice(allocator, "))\n" ++
        "    (local $__result_area i32)\n" ++
        "    (local $__record_bytes i32)\n" ++
        "    (local $__memory_bytes i64)\n" ++
        "    (local $__text_ptr i32)\n" ++
        "    (local $__text_length i32)\n" ++
        "    (local $__text_index i32)\n" ++
        "    (local $__text_bytes (ref $do_bytes))\n" );
    if (has_record_list) {
        try out.appendSlice(allocator,
            "    (local $__list_ptr i32)\n" ++
                "    (local $__list_length i32)\n" ++
                "    (local $__list_index i32)\n" ++
                "    (local $__list_copy_bytes i32)\n" ++
                "    (local $__list_copy_bytes64 i64)\n");
        if (has_record_u32_list) {
            try out.appendSlice(allocator, "    (local $__list_array (ref $do_u32))\n");
        }
        if (has_record_byte_list) {
            try out.appendSlice(allocator, "    (local $__byte_list_array (ref $do_bytes))\n");
        }
    }
    try out.appendSlice(allocator,
        "    i32.const 0\n" ++
        "    local.set $__result_area\n" ++
        "    local.get $__result_area\n");
    try append_named_call(allocator, out, config.canonical_call_name);
    try append_fmt(allocator, out, "    i32.const {d}\n" ++
        "    local.set $__record_bytes\n", .{measured.byte_size});
    try emit_span_guard(allocator, out, "__result_area", "__record_bytes");

    try emit_record_lift_value(allocator, out, &plan.root, 0, true, config.realloc_name);
    try out.appendSlice(allocator, "    struct.new ");
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try out.appendSlice(allocator, ")\n");
}

fn emit_record_lift_value(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
    base_offset: u32,
    is_root: bool,
    realloc_name: []const u8,
) !void {
    if (node.kind != .record and node.kind != .scalar and node.kind != .text and node.kind != .list) {
        return error.UnsupportedMarshalShape;
    }
    switch (node.kind) {
        .scalar => {
            const facts = node.measured orelse return error.MeasuredChildMissing;
            const core_type = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
            const offset = std.math.add(u32, base_offset, facts.offset) catch return error.OffsetOverflow;
            const load_name = switch (core_type) {
                .i32 => "i32.load",
                .i64 => "i64.load",
                .f32 => "f32.load",
                .f64 => "f64.load",
            };
            try append_fmt(allocator, out, "    local.get $__result_area\n" ++
                "    i32.const {d}\n" ++
                "    i32.add\n" ++
                "    {s}\n", .{ offset, load_name });
        },
        .text => {
            const facts = node.measured orelse return error.MeasuredChildMissing;
            const pointer_offset = facts.pointer_offset orelse return error.MeasuredResultAreaPointerMissing;
            const length_offset = facts.length_offset orelse return error.MeasuredResultAreaLengthMissing;
            const field_offset = std.math.add(u32, base_offset, facts.offset) catch return error.OffsetOverflow;
            const pointer = std.math.add(u32, field_offset, pointer_offset) catch return error.OffsetOverflow;
            const length = std.math.add(u32, field_offset, length_offset) catch return error.OffsetOverflow;
            try append_fmt(allocator, out, "    local.get $__result_area\n" ++
                "    i32.const {d}\n" ++
                "    i32.add\n" ++
                "    i32.load\n" ++
                "    local.set $__text_ptr\n" ++
                "    local.get $__result_area\n" ++
                "    i32.const {d}\n" ++
                "    i32.add\n" ++
                "    i32.load\n" ++
                "    local.set $__text_length\n", .{ pointer, length });
            try emit_span_guard(allocator, out, "__text_ptr", "__text_length");
            try append_fmt(allocator, out, "    local.get $__text_length\n" ++
                "    array.new_default $do_bytes\n" ++
                "    local.set $__text_bytes\n" ++
                "    i32.const 0\n" ++
                "    local.set $__text_index\n" ++
                "    block $__text_copy_done\n" ++
                "      loop $__text_copy\n" ++
                "        local.get $__text_index\n" ++
                "        local.get $__text_length\n" ++
                "        i32.ge_u\n" ++
                "        br_if $__text_copy_done\n" ++
                "        local.get $__text_bytes\n" ++
                "        local.get $__text_index\n" ++
                "        local.get $__text_ptr\n" ++
                "        local.get $__text_index\n" ++
                "        i32.add\n" ++
                "        i32.load8_u\n" ++
                "        array.set $do_bytes\n" ++
                "        local.get $__text_index\n" ++
                "        i32.const 1\n" ++
                "        i32.add\n" ++
                "        local.set $__text_index\n" ++
                "        br $__text_copy\n" ++
                "      end\n" ++
                "    end\n" ++
                "    local.get $__text_ptr\n" ++
                "    local.get $__text_length\n" ++
                "    i32.const 1\n" ++
                "    i32.const 0\n" ++
                "    call ${s}\n" ++
                "    drop\n" ++
                "    local.get $__text_length\n" ++
                "    local.get $__text_bytes\n" ++
                "    struct.new $do_text\n", .{realloc_name});
        },
        .list => {
            if (node.children.len != 1) return error.UnsupportedMarshalShape;
            const facts = node.measured orelse return error.MeasuredChildMissing;
            if (facts.pointer_offset == null or facts.length_offset == null) {
                return error.UnsupportedMarshalShape;
            }
            const element = &node.children[0];
            if (element.kind != .scalar) return error.UnsupportedMarshalShape;
            const element_facts = element.measured orelse return error.MeasuredChildMissing;
            const is_byte_list = element.scalar_kind == .u8;
            const array_type = if (is_byte_list) "$do_bytes" else "$do_u32";
            const array_local = if (is_byte_list) "__byte_list_array" else "__list_array";
            const stride: u32 = if (is_byte_list) 1 else 4;
            if (facts.element_stride != stride) return error.UnsupportedMarshalShape;
            if (is_byte_list) {
                if (element_facts.byte_size != 1 or element_facts.alignment != 1) {
                    return error.UnsupportedMarshalShape;
                }
            } else if (element.scalar_kind != .u32 or element_facts.core_type != .i32 or
                element_facts.byte_size != 4 or element_facts.alignment != 4)
            {
                return error.UnsupportedMarshalShape;
            }
            const field_offset = std.math.add(u32, base_offset, facts.offset) catch return error.OffsetOverflow;
            const pointer = std.math.add(u32, field_offset, facts.pointer_offset.?) catch return error.OffsetOverflow;
            const length = std.math.add(u32, field_offset, facts.length_offset.?) catch return error.OffsetOverflow;
            try append_fmt(allocator, out, "    local.get $__result_area\n" ++
                "    i32.const {d}\n" ++
                "    i32.add\n" ++
                "    i32.load\n" ++
                "    local.set $__list_ptr\n" ++
                "    local.get $__result_area\n" ++
                "    i32.const {d}\n" ++
                "    i32.add\n" ++
                "    i32.load\n" ++
                "    local.set $__list_length\n", .{ pointer, length });
            try append_fmt(allocator, out, "    local.get $__list_length\n" ++
                "    i64.extend_i32_u\n" ++
                "    i64.const {d}\n" ++
                "    i64.mul\n" ++
                "    local.tee $__list_copy_bytes64\n" ++
                "    i64.const 4294967295\n" ++
                "    i64.gt_u\n" ++
                "    if unreachable end\n" ++
                "    local.get $__list_copy_bytes64\n" ++
                "    i32.wrap_i64\n" ++
                "    local.set $__list_copy_bytes\n", .{stride});
            try emit_span_guard(allocator, out, "__list_ptr", "__list_copy_bytes");
            try append_fmt(allocator, out,
                "    local.get $__list_length\n" ++
                    "    array.new_default {s}\n" ++
                    "    local.set ${s}\n" ++
                    "    i32.const 0\n" ++
                    "    local.set $__list_index\n" ++
                    "    block $__list_copy_done\n" ++
                    "      loop $__list_copy\n" ++
                    "        local.get $__list_index\n" ++
                    "        local.get $__list_length\n" ++
                    "        i32.ge_u\n" ++
                    "        br_if $__list_copy_done\n" ++
                    "        local.get ${s}\n" ++
                    "        local.get $__list_index\n" ++
                    "        local.get $__list_ptr\n" ++
                    "        local.get $__list_index\n" ++
                    "        i32.const {d}\n" ++
                    "        i32.mul\n" ++
                    "        i32.add\n" ++
                    "        {s}\n" ++
                    "        array.set {s}\n" ++
                    "        local.get $__list_index\n" ++
                    "        i32.const 1\n" ++
                    "        i32.add\n" ++
                    "        local.set $__list_index\n" ++
                    "        br $__list_copy\n" ++
                    "      end\n" ++
                    "    end\n", .{ array_type, array_local, array_local, stride, if (is_byte_list) "i32.load8_u" else "i32.load", array_type });
            try append_fmt(allocator, out, "    local.get $__list_ptr\n" ++
                "    local.get $__list_copy_bytes\n" ++
                "    i32.const {d}\n" ++
                "    i32.const 0\n" ++
                "    call ${s}\n" ++
                "    drop\n" ++
                "    local.get ${s}\n", .{ stride, realloc_name, array_local });
        },
        .record => {
            const measured = node.measured orelse return error.MeasuredChildMissing;
            const record_offset = if (is_root)
                base_offset
            else
                std.math.add(u32, base_offset, measured.offset) catch return error.OffsetOverflow;
            for (node.children) |*child| {
                try emit_record_lift_value(allocator, out, child, record_offset, false, realloc_name);
            }
            if (is_root) return;
            const name = node.record_type_name orelse return error.UnsupportedMarshalShape;
            if (!valid_wat_name(name)) return error.InvalidWatName;
            try append_fmt(allocator, out, "    struct.new $do_{s}\n", .{name});
        },
    }
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

    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null ", .{ config.function_name, config.input_local });
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try out.appendSlice(allocator, "))\n");

    if (memory_plan.record_managed_text_lower) {
        try emit_record_lower_managed_text(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_managed_scalar_list_lower) {
        try emit_record_lower_managed_scalar_list(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_indirect != null) {
        try out.appendSlice(allocator, "    (local $__cabi_ptr i32)\n" ++
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

        var path = std.ArrayList(RecordPathSegment).empty;
        defer path.deinit(allocator);
        try emit_record_lower_fields(allocator, out, &plan.root, 0, true, config.input_local, config.root_type_name, &path);

        try out.appendSlice(allocator, "    local.get $__cabi_ptr\n");
        try append_named_call(allocator, out, config.canonical_call_name);
        try out.appendSlice(allocator, "    local.get $__cabi_ptr\n");
        try append_fmt(allocator, out, "    i32.const {d}\n    i32.const {d}\n    i32.const 0\n", .{ measured.byte_size, measured.alignment });
        try append_named_call(allocator, out, config.realloc_name);
        try out.appendSlice(allocator, "    drop)\n");
        return;
    }

    var path = std.ArrayList(RecordPathSegment).empty;
    defer path.deinit(allocator);
    try emit_record_lower_flat_values(allocator, out, &plan.root, true, config.input_local, config.root_type_name, &path);

    try append_named_call(allocator, out, config.canonical_call_name);
    try out.appendSlice(allocator, ")\n");
}

fn emit_record_lower_managed_text(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const root = &plan.root;
    if (root.kind != .record or root.children.len != memory_plan.record_field_count) return error.UnsupportedMarshalShape;
    const field_count: usize = @intCast(memory_plan.managed_text_field_count);
    if (field_count == 0 or field_count > memory_plan.managed_text_fields.len) {
        return error.UnsupportedMarshalShape;
    }

    try out.appendSlice(allocator, "    (local $__memory_bytes i64)\n");
    for (0..field_count) |slot| {
        try append_fmt(allocator, out, "    (local $__gc_length_{d} i32)\n" ++
            "    (local $__gc_index_{d} i32)\n" ++
            "    (local $__cabi_ptr_{d} i32)\n", .{ slot, slot, slot });
    }

    var text_path = std.ArrayList(RecordPathSegment).empty;
    defer text_path.deinit(allocator);
    for (memory_plan.managed_text_fields[0..field_count], 0..) |field, slot| {
        const field_index: usize = @intCast(field.field_index);
        if (field_index >= root.children.len) return error.UnsupportedMarshalShape;
        const text = &root.children[field_index];
        if (text.kind != .text) return error.UnsupportedMarshalShape;
        if (field.pointer_offset != 0 or field.length_offset != 4) {
            return error.UnsupportedMarshalShape;
        }

        text_path.items.len = 0;
        try text_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = field_index });
        try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
        try append_fmt(allocator, out, "    ref.as_non_null\n" ++
            "    struct.get $do_text $length\n" ++
            "    local.set $__gc_length_{d}\n", .{slot});

        try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
        try append_fmt(allocator, out, "    ref.as_non_null\n" ++
            "    struct.get $do_text $bytes\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    local.get $__gc_length_{d}\n" ++
            "    i32.lt_u\n" ++
            "    if unreachable end\n" ++
            "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    i32.const 1\n" ++
            "    local.get $__gc_length_{d}\n", .{ slot, slot });
        try append_named_call(allocator, out, config.realloc_name);
        try append_fmt(allocator, out, "    local.set $__cabi_ptr_{d}\n", .{slot});
        const pointer_local = try std.fmt.allocPrint(allocator, "__cabi_ptr_{d}", .{slot});
        defer allocator.free(pointer_local);
        const length_local = try std.fmt.allocPrint(allocator, "__gc_length_{d}", .{slot});
        defer allocator.free(length_local);
        try emit_span_guard(allocator, out, pointer_local, length_local);
        try append_fmt(allocator, out, "    i32.const 0\n" ++
            "    local.set $__gc_index_{d}\n" ++
            "    block $__copy_done_{d}\n" ++
            "      loop $__copy_{d}\n" ++
            "        local.get $__gc_index_{d}\n" ++
            "        local.get $__gc_length_{d}\n" ++
            "        i32.ge_u\n" ++
            "        br_if $__copy_done_{d}\n" ++
            "        local.get $__cabi_ptr_{d}\n" ++
            "        local.get $__gc_index_{d}\n" ++
            "        i32.add\n", .{ slot, slot, slot, slot, slot, slot, slot, slot });
        try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
        try append_fmt(allocator, out, "        ref.as_non_null\n" ++
            "        struct.get $do_text $bytes\n" ++
            "        ref.as_non_null\n" ++
            "        local.get $__gc_index_{d}\n" ++
            "        array.get_s $do_bytes\n" ++
            "        i32.store8\n" ++
            "        local.get $__gc_index_{d}\n" ++
            "        i32.const 1\n" ++
            "        i32.add\n" ++
            "        local.set $__gc_index_{d}\n" ++
            "        br $__copy_{d}\n" ++
            "      end\n" ++
            "    end\n", .{ slot, slot, slot, slot });
    }

    var code_path = std.ArrayList(RecordPathSegment).empty;
    defer code_path.deinit(allocator);
    try code_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 0 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, code_path.items);
    for (0..field_count) |slot| {
        try append_fmt(allocator, out, "    local.get $__cabi_ptr_{d}\n" ++
            "    local.get $__gc_length_{d}\n", .{ slot, slot });
    }
    try append_named_call(allocator, out, config.canonical_call_name);

    var free_slot = field_count;
    while (free_slot > 0) {
        free_slot -= 1;
        try append_fmt(allocator, out, "    local.get $__cabi_ptr_{d}\n" ++
            "    local.get $__gc_length_{d}\n" ++
            "    i32.const 1\n" ++
            "    i32.const 0\n", .{ free_slot, free_slot });
        try append_named_call(allocator, out, config.realloc_name);
        try out.appendSlice(allocator, "    drop\n");
    }
    try out.appendSlice(allocator, ")\n");
}

fn scalar_list_gc_type(kind: marshal_ops.ScalarListElementKind) []const u8 {
    return switch (kind) {
        .byte => "$do_bytes",
        .u32 => "$do_u32",
    };
}

fn scalar_list_load_instruction(kind: marshal_ops.ScalarListElementKind) []const u8 {
    return switch (kind) {
        .byte => "array.get_s $do_bytes",
        .u32 => "array.get $do_u32",
    };
}

fn scalar_list_store_instruction(kind: marshal_ops.ScalarListElementKind) []const u8 {
    return switch (kind) {
        .byte => "i32.store8",
        .u32 => "i32.store",
    };
}

fn emit_record_lower_managed_scalar_list(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const root = &plan.root;
    if (root.kind != .record or root.children.len != memory_plan.record_field_count) {
        return error.UnsupportedMarshalShape;
    }
    const field = memory_plan.managed_scalar_list_field orelse return error.UnsupportedMarshalShape;
    if (field.field_index >= root.children.len or field.pointer_offset != 0 or field.length_offset != 4 or
        field.capacity == 0)
    {
        return error.UnsupportedMarshalShape;
    }
    if (root.children[0].kind != .scalar or root.children[1].kind != .list) {
        return error.UnsupportedMarshalShape;
    }
    const payload = &root.children[field.field_index];
    if (payload.children.len != 1) return error.UnsupportedMarshalShape;
    const element = &payload.children[0];
    if (element.kind != .scalar) return error.UnsupportedMarshalShape;
    const expected_stride: u32 = switch (field.element_kind) {
        .byte => 1,
        .u32 => 4,
    };
    if (field.element_byte_size != expected_stride or field.element_alignment != expected_stride or
        field.element_stride != expected_stride)
    {
        return error.UnsupportedMarshalShape;
    }
    switch (field.element_kind) {
        .byte => if (element.scalar_kind != .u8) return error.UnsupportedMarshalShape,
        .u32 => if (element.scalar_kind != .u32) return error.UnsupportedMarshalShape,
    }
    const element_facts = element.measured orelse return error.MeasuredChildMissing;
    if (element_facts.byte_size != expected_stride or element_facts.alignment != expected_stride) {
        return error.UnsupportedMarshalShape;
    }
    switch (field.element_kind) {
        .byte => if (element_facts.core_type != null) return error.UnsupportedMarshalShape,
        .u32 => if (element_facts.core_type != .i32) return error.UnsupportedMarshalShape,
    }

    const array_type = scalar_list_gc_type(field.element_kind);
    const load_instruction = scalar_list_load_instruction(field.element_kind);
    const store_instruction = scalar_list_store_instruction(field.element_kind);
    try append_fmt(allocator, out,
        "    (local $__gc_length i32)\n" ++
            "    (local $__gc_index i32)\n" ++
            "    (local $__copy_bytes i32)\n" ++
            "    (local $__copy_bytes64 i64)\n" ++
            "    (local $__cabi_ptr i32)\n" ++
            "    (local $__memory_bytes i64)\n" ++
            "    (local $__gc_values (ref {s}))\n", .{array_type});

    var payload_path = std.ArrayList(RecordPathSegment).empty;
    defer payload_path.deinit(allocator);
    try payload_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = field.field_index });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, payload_path.items);
    try append_fmt(allocator, out,
        "    ref.as_non_null\n" ++
            "    local.set $__gc_values\n" ++
            "    local.get $__gc_values\n" ++
            "    array.len\n" ++
            "    local.set $__gc_length\n" ++
            "    local.get $__gc_length\n" ++
            "    i32.const {d}\n" ++
            "    i32.gt_u\n" ++
            "    if unreachable end\n", .{field.capacity});
    try append_copy_byte_count(allocator, out, field.element_stride);
    try append_fmt(allocator, out,
        "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    i32.const {d}\n" ++
            "    local.get $__copy_bytes\n", .{field.element_alignment});
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");

    try out.appendSlice(allocator,
        "    i32.const 0\n" ++
            "    local.set $__gc_index\n" ++
            "    block $__copy_done\n" ++
            "      loop $__copy\n" ++
            "        local.get $__gc_index\n" ++
            "        local.get $__gc_length\n" ++
            "        i32.ge_u\n" ++
            "        br_if $__copy_done\n" ++
            "        local.get $__cabi_ptr\n");
    if (field.element_stride == 1) {
        try out.appendSlice(allocator, "        local.get $__gc_index\n        i32.add\n");
    } else {
        try append_fmt(allocator, out, "        local.get $__gc_index\n        i32.const {d}\n        i32.mul\n        i32.add\n", .{field.element_stride});
    }
    try out.appendSlice(allocator, "        local.get $__gc_values\n        local.get $__gc_index\n");
    try append_fmt(allocator, out, "        {s}\n        {s}\n", .{ load_instruction, store_instruction });
    try out.appendSlice(allocator,
        "        local.get $__gc_index\n" ++
            "        i32.const 1\n" ++
            "        i32.add\n" ++
            "        local.set $__gc_index\n" ++
            "        br $__copy\n" ++
            "      end\n" ++
            "    end\n");

    var code_path = std.ArrayList(RecordPathSegment).empty;
    defer code_path.deinit(allocator);
    try code_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 0 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, code_path.items);
    try out.appendSlice(allocator, "    local.get $__cabi_ptr\n    local.get $__gc_length\n");
    try append_named_call(allocator, out, config.canonical_call_name);
    try append_fmt(allocator, out,
        "    local.get $__cabi_ptr\n" ++
            "    local.get $__copy_bytes\n" ++
            "    i32.const {d}\n" ++
            "    i32.const 0\n", .{field.element_alignment});
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    drop)\n");
}

fn emit_record_lower_flat_values(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
    is_root: bool,
    input_local: []const u8,
    root_type_name: []const u8,
    path: *std.ArrayList(RecordPathSegment),
) !void {
    if (node.kind != .record or node.children.len == 0) return error.UnsupportedMarshalShape;
    const record_name = if (is_root) "record" else (node.record_type_name orelse return error.UnsupportedMarshalShape);
    if (!is_root and !valid_wat_name(record_name)) return error.InvalidWatName;
    for (node.children, 0..) |*child, index| {
        const previous_len = path.items.len;
        try path.append(allocator, .{ .type_name = record_name, .is_root = is_root, .field_index = index });
        switch (child.kind) {
            .record => try emit_record_lower_flat_values(allocator, out, child, false, input_local, root_type_name, path),
            .scalar => {
                _ = child.measured orelse return error.MeasuredChildMissing;
                _ = child.measured.?.core_type orelse return error.MeasuredScalarCoreTypeMissing;
                try emit_record_lower_input_path(allocator, out, input_local, root_type_name, path.items);
            },
            else => return error.UnsupportedMarshalShape,
        }
        path.items.len = previous_len;
    }
}

fn emit_record_lower_fields(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    node: *const marshal.MarshalNode,
    base_offset: u32,
    is_root: bool,
    input_local: []const u8,
    root_type_name: []const u8,
    path: *std.ArrayList(RecordPathSegment),
) !void {
    if (node.kind != .record or node.children.len == 0) return error.UnsupportedMarshalShape;
    const measured = node.measured orelse return error.MeasuredChildMissing;
    const record_offset = if (is_root)
        base_offset
    else
        std.math.add(u32, base_offset, measured.offset) catch return error.OffsetOverflow;
    const record_name = if (is_root) "record" else (node.record_type_name orelse return error.UnsupportedMarshalShape);
    if (!is_root and !valid_wat_name(record_name)) return error.InvalidWatName;

    for (node.children, 0..) |*child, index| {
        const previous_len = path.items.len;
        try path.append(allocator, .{ .type_name = record_name, .is_root = is_root, .field_index = index });
        switch (child.kind) {
            .record => try emit_record_lower_fields(allocator, out, child, record_offset, false, input_local, root_type_name, path),
            .scalar => {
                const facts = child.measured orelse return error.MeasuredChildMissing;
                const absolute_offset = std.math.add(u32, record_offset, facts.offset) catch return error.OffsetOverflow;
                const core_type = facts.core_type orelse return error.MeasuredScalarCoreTypeMissing;
                const store_name = switch (core_type) {
                    .i32 => "i32.store",
                    .i64 => "i64.store",
                    .f32 => "f32.store",
                    .f64 => "f64.store",
                };
                try append_fmt(allocator, out, "    local.get $__cabi_ptr\n", .{});
                try emit_record_lower_input_path(allocator, out, input_local, root_type_name, path.items);
                if (absolute_offset == 0) {
                    try append_fmt(allocator, out, "    {s}\n", .{store_name});
                } else {
                    try append_fmt(allocator, out, "    {s} offset={d}\n", .{ store_name, absolute_offset });
                }
            },
            else => return error.UnsupportedMarshalShape,
        }
        path.items.len = previous_len;
    }
}

fn emit_record_lower_input_path(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    input_local: []const u8,
    root_type_name: []const u8,
    path: []const RecordPathSegment,
) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n", .{input_local});
    for (path, 0..) |segment, index| {
        if (segment.is_root) {
            try out.appendSlice(allocator, "    struct.get ");
            try append_lowercase_wat_name(allocator, out, root_type_name);
            // Standalone marshal probes declare `$do_record` with synthetic
            // `$fieldN` names. Compiler GC structs keep source field names,
            // so the ordinary route uses the stable numeric field index.
            if (std.mem.eql(u8, root_type_name, "do_record")) {
                try append_fmt(allocator, out, " $field{d}\n", .{segment.field_index});
            } else {
                try append_fmt(allocator, out, " {d}\n", .{segment.field_index});
            }
        } else {
            try append_fmt(allocator, out, "    struct.get $do_{s} $field{d}\n", .{ segment.type_name, segment.field_index });
        }
        if (index + 1 < path.len) try out.appendSlice(allocator, "    ref.as_non_null\n");
    }
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

test "canonical marshal WAT lowers two managed text fields before reverse frees" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var note = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer note.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "note", .value = &note },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-managed-lower-multi@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "note", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
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
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{});
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $canonical_call"));
    const call_index = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    const first_alloc = std.mem.indexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    const last_free = std.mem.lastIndexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    try std.testing.expect(first_alloc < call_index);
    try std.testing.expect(call_index < last_free);
    const first_free = std.mem.indexOf(u8, wat, "local.get $__cabi_ptr_1\n" ++
        "    local.get $__gc_length_1\n" ++
        "    i32.const 1\n" ++
        "    i32.const 0\n" ++
        "    call $cabi_realloc") orelse unreachable;
    const second_free = std.mem.indexOf(u8, wat, "local.get $__cabi_ptr_0\n" ++
        "    local.get $__gc_length_0\n" ++
        "    i32.const 1\n" ++
        "    i32.const 0\n" ++
        "    call $cabi_realloc") orelse unreachable;
    try std.testing.expect(call_index < first_free);
    try std.testing.expect(first_free < second_free);
}

test "canonical marshal WAT lowers a managed text record with compiler root field indices" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-managed-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 12,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
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
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Writing",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $writing))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $writing 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $writing 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $writing $field0") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $writing $field1") == null);
}

test "canonical marshal WAT lowers bounded record byte-list with numeric root fields" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Writing",
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $writing))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $writing 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $writing 1") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "i32.store8"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "$do_text") == null);

    const copy = std.mem.indexOf(u8, wat, "array.get_s $do_bytes") orelse unreachable;
    const call = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    const first_realloc = std.mem.indexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    const last_realloc = std.mem.lastIndexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    try std.testing.expect(first_realloc < copy);
    try std.testing.expect(copy < call);
    try std.testing.expect(call < last_realloc);
}

test "canonical marshal WAT lowers bounded record u32-list with numeric root fields" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Writing",
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $writing))") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "array.get $do_u32"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "i32.store"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get_s $do_bytes") == null);

    const copy = std.mem.indexOf(u8, wat, "array.get $do_u32") orelse unreachable;
    const call = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    const first_realloc = std.mem.indexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    const last_realloc = std.mem.lastIndexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    try std.testing.expect(first_realloc < copy);
    try std.testing.expect(copy < call);
    try std.testing.expect(call < last_realloc);
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
