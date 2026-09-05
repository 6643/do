//! Bounded synchronous WAT emission for measured text and byte-list plans.
//!
//! This module emits a core-module fragment only. It does not admit the
//! host/WIT route by itself; callers must still provide the pinned descriptor
//! and keep component assembly behind the G5c gate.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const marshal_ops = @import("codegen_component_marshal_ops.zig");
const wit_abi_types = @import("wit_abi_types.zig");
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

const CleanupBinding = struct {
    pointer_local: []const u8,
    length_local: []const u8,
    size_local: ?[]const u8 = null,
    alignment: u32 = 1,
};

const MapValueKind = enum {
    u32,
    text,
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
        .map_entries => switch (memory_plan.direction) {
            .lower => try emit_map_lower(allocator, &out, plan, &memory_plan, config),
            .lift => try emit_map_lift(allocator, &out, plan, &memory_plan, config),
        },
        .record_fields => switch (memory_plan.direction) {
            .lower => try emit_record_lower(allocator, &out, plan, &memory_plan, config),
            .lift => try emit_record_lift(allocator, &out, plan, &memory_plan, config),
        },
    }
    const body = try out.toOwnedSlice(allocator);
    return prepend_linear_temp_marker(allocator, body, config.realloc_name);
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
            try append_fmt(allocator, &out, "  (func ${[function_name]s}", .{ .function_name = config.function_name });
            _ = try append_scalar_record_param_types(allocator, &out, &plan.root, 0);
            try out.appendSlice(allocator, "\n");
            for (0..leaf_count) |index| {
                try append_fmt(allocator, &out, "    local.get $__gc_arg_{[index]d}\n", .{ .index = index });
            }
            try append_fmt(allocator, &out, "    call ${[canonical_call_name]s})\n", .{ .canonical_call_name = config.canonical_call_name });
        },
        .lift => {
            if (plan.abi.arguments.len != 0 or plan.abi.results.len != 1) return error.InvalidCanonicalArity;
            try append_fmt(allocator, &out, "  (func ${[function_name]s} (result", .{ .function_name = config.function_name });
            try append_scalar_record_result_types(allocator, &out, &plan.root);
            try generated_text.append_block(allocator, &out, 0,
                \\)
                \\    (local $__result_area i32)
                \\    i32.const 0
                \\    local.set $__result_area
                \\
            );
            try generated_text.append_fmt_block(allocator, &out, 4,
                \\    local.get $__result_area
                \\    call ${[canonical_call_name]s}
                \\
            , .{ .canonical_call_name = config.canonical_call_name });
            try emit_scalar_record_loads(allocator, &out, &plan.root, 0, true);
            try out.appendSlice(allocator, "  )\n");
        },
    }
    const body = try out.toOwnedSlice(allocator);
    return prepend_linear_temp_marker(allocator, body, config.realloc_name);
}

fn prepend_linear_temp_marker(
    allocator: std.mem.Allocator,
    body: []u8,
    realloc_name: []const u8,
) ![]u8 {
    errdefer allocator.free(body);

    var free_count: usize = 0;
    var previous_was_zero = false;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.eql(u8, trimmed, "i32.const 0")) {
            previous_was_zero = true;
            continue;
        }
        if (previous_was_zero and std.mem.startsWith(u8, trimmed, "call $") and
            std.mem.eql(u8, trimmed["call $".len..], realloc_name))
        {
            free_count += 1;
        }
        previous_was_zero = false;
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try generated_text.append_fmt(allocator, &out, "  ;; [linear-temp-free] count={[count]d}\n", .{ .count = free_count });
    try out.appendSlice(allocator, body);
    const result = try out.toOwnedSlice(allocator);
    allocator.free(body);
    return result;
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
            try append_fmt(allocator, out, " (param $__gc_arg_{[index]d} {[core_type]s})", .{ .index = index, .core_type = core_type_name(core_type) });
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
            try append_fmt(allocator, out, " {[core_type]s}", .{ .core_type = core_type_name(core_type) });
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
            try generated_text.append_fmt_block(
                allocator,
                out,
                4,
                \\    local.get $__result_area
                \\    i32.const {[offset]d}
                \\    i32.add
                \\    {[load_name]s}
                \\
            ,
                .{ .offset = offset, .load_name = scalar_load_name(core_type) },
            );
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
        .lower => try generated_text.append_fmt_block(
            allocator,
            out,
            2,
            \\  (func ${[function_name]s} (param ${[input_local]s} {[core_name]s})
            \\    local.get ${[input_local]s}
            \\    call ${[canonical_call_name]s})
            \\
        ,
            .{
                .function_name = config.function_name,
                .input_local = config.input_local,
                .core_name = core_name,
                .canonical_call_name = config.canonical_call_name,
            },
        ),
        .lift => try generated_text.append_fmt_block(
            allocator,
            out,
            2,
            \\  (func ${[function_name]s} (result {[core_name]s})
            \\    call ${[canonical_call_name]s})
            \\
        ,
            .{
                .function_name = config.function_name,
                .core_name = core_name,
                .canonical_call_name = config.canonical_call_name,
            },
        ),
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
        .map_entries => return error.UnsupportedMarshalShape,
        .record_fields => return error.UnsupportedMarshalShape,
    };
    try generated_text.append_fmt_block(
        allocator,
        out,
        2,
        \\  (func ${[function_name]s} (param ${[input_local]s} {[source_type]s})
        \\    (local $__gc_length i32)
        \\    (local $__gc_index i32)
        \\    (local $__copy_bytes i32)
        \\    (local $__copy_bytes64 i64)
        \\    (local $__cabi_ptr i32)
        \\    (local $__memory_bytes i64)
        \\
    ,
        .{
            .function_name = config.function_name,
            .input_local = config.input_local,
            .source_type = source_type,
        },
    );

    try append_source_length(allocator, out, memory_plan.copy_shape, config.input_local);
    try append_copy_byte_count(allocator, out, memory_plan.element_stride);
    try append_source_length_guard(allocator, out, memory_plan.copy_shape, config.input_local);
    try generated_text.append_fmt_block(
        allocator,
        out,
        4,
        \\    i32.const 0
        \\    i32.const 0
        \\    i32.const{[space]s}
    ,
        .{ .space = " " },
    );
    try generated_text.append_fmt_block(allocator, out, 0,
        \\{[element_stride]d}
        \\    local.get $__copy_bytes
        \\
    , .{ .element_stride = memory_plan.element_stride });
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__gc_index
        \\block $__copy_done
        \\  loop $__copy
        \\    local.get $__gc_index
        \\    local.get $__gc_length
        \\    i32.ge_u
        \\    br_if $__copy_done
        \\    local.get $__cabi_ptr
        \\    local.get $__gc_index
        \\
    );
    if (memory_plan.element_stride != 1) {
        try generated_text.append_fmt_block(allocator, out, 8,
            \\        i32.const {[element_stride]d}
            \\        i32.mul
            \\
        , .{ .element_stride = memory_plan.element_stride });
    }
    try out.appendSlice(allocator, "        i32.add\n");
    try append_source_element(allocator, out, memory_plan, config.input_local);
    if (memory_plan.element_stride == 1) {
        try out.appendSlice(allocator, "        i32.store8\n");
    } else {
        try out.appendSlice(allocator, "        i32.store\n");
    }
    try generated_text.append_block(allocator, out, 8,
        \\local.get $__gc_index
        \\i32.const 1
        \\i32.add
        \\local.set $__gc_index
        \\br $__copy
        \\  end
        \\end
        \\local.get $__cabi_ptr
        \\local.get $__gc_length
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__cabi_ptr
        \\local.get $__copy_bytes
        \\i32.const {[stride]d}
        \\
    , .{ .stride = memory_plan.element_stride });
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
        .map_entries => return error.UnsupportedMarshalShape,
        .record_fields => return error.UnsupportedMarshalShape,
    };
    const array_type = if (memory_plan.element_core_type != null) "$do_u32" else "$do_bytes";
    try generated_text.append_fmt_block(
        allocator,
        out,
        2,
        \\  (func ${[function_name]s} (result {[result_type]s})
        \\    (local $__cabi_ptr i32)
        \\    (local $__result_area i32)
        \\    (local $__gc_length i32)
        \\    (local $__gc_index i32)
        \\    (local $__copy_bytes i32)
        \\    (local $__copy_bytes64 i64)
        \\    (local $__memory_bytes i64)
        \\    (local $__gc_bytes (ref {[array_type]s}))
        \\    (local $__gc_result {[result_type]s})
        \\
    ,
        .{
            .function_name = config.function_name,
            .result_type = result_type,
            .array_type = array_type,
        },
    );
    // Canonical list/text results write `(ptr, len)` into the measured result area.
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__result_area
        \\
    );
    if (config.canonical_u64_arg) |arg| {
        try append_fmt(allocator, out, "    i64.const {[canonical_u64_arg]d}\n", .{ .canonical_u64_arg = arg });
    }
    try out.appendSlice(allocator, "    local.get $__result_area\n");
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(
        allocator,
        out,
        4,
        \\    local.get $__result_area
        \\    i32.const {[pointer_offset]d}
        \\    i32.add
        \\    i32.load
        \\    local.set $__cabi_ptr
        \\    local.get $__result_area
        \\    i32.const {[length_offset]d}
        \\    i32.add
        \\    i32.load
        \\    local.set $__gc_length
        \\
    ,
        .{ .pointer_offset = result_area_pointer_offset, .length_offset = result_area_length_offset },
    );
    try append_copy_byte_count(allocator, out, memory_plan.element_stride);
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");
    try generated_text.append_fmt_block(
        allocator,
        out,
        4,
        \\    local.get $__gc_length
        \\    array.new_default{[space]s}
    ,
        .{ .space = " " },
    );
    try out.appendSlice(allocator, array_type);
    try generated_text.append_block(allocator, out, 4,
        \\
        \\local.set $__gc_bytes
        \\i32.const 0
        \\local.set $__gc_index
        \\block $__copy_done
        \\  loop $__copy
        \\    local.get $__gc_index
        \\    local.get $__gc_length
        \\    i32.ge_u
        \\    br_if $__copy_done
        \\    local.get $__gc_bytes
        \\    local.get $__gc_index
        \\    local.get $__cabi_ptr
        \\    local.get $__gc_index
        \\
    );
    if (memory_plan.element_stride != 1) {
        try generated_text.append_fmt_block(allocator, out, 8,
            \\        i32.const {[element_stride]d}
            \\        i32.mul
            \\
        , .{ .element_stride = memory_plan.element_stride });
    }
    try out.appendSlice(allocator, "        i32.add\n");
    if (memory_plan.element_stride == 1) {
        try out.appendSlice(allocator, "        i32.load8_u\n");
    } else {
        try out.appendSlice(allocator, "        i32.load\n");
    }
    try append_fmt(allocator, out, "        array.set {[array_type]s}\n", .{ .array_type = array_type });
    try generated_text.append_block(allocator, out, 8,
        \\local.get $__gc_index
        \\i32.const 1
        \\i32.add
        \\local.set $__gc_index
        \\br $__copy
        \\  end
        \\end
        \\
    );
    switch (memory_plan.copy_shape) {
        .scalar => return error.UnsupportedMarshalShape,
        .text_bytes => try generated_text.append_block(allocator, out, 4,
            \\local.get $__gc_length
            \\local.get $__gc_bytes
            \\struct.new $do_text
            \\local.set $__gc_result
            \\
        ),
        .list_elements => try generated_text.append_block(allocator, out, 4,
            \\local.get $__gc_bytes
            \\local.set $__gc_result
            \\
        ),
        .map_entries => return error.UnsupportedMarshalShape,
        .record_fields => return error.UnsupportedMarshalShape,
    }
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__cabi_ptr
        \\local.get $__copy_bytes
        \\i32.const {[element_stride]d}
        \\
    , .{ .element_stride = memory_plan.element_stride });
    try out.appendSlice(allocator, "    i32.const 0\n");
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\drop
        \\local.get $__gc_result)
        \\
    );
}

fn emit_map_lower(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const value_kind = try validate_u32_key_map(plan, memory_plan);
    if (value_kind == .text) {
        return emit_map_lower_text(allocator, out, plan, memory_plan, config);
    }
    const key_offset = memory_plan.map_key_offset orelse return error.MeasuredMapFieldMissing;
    const value_offset = memory_plan.map_value_offset orelse return error.MeasuredMapFieldMissing;
    const stride = memory_plan.element_stride;

    try generated_text.append_fmt_block(allocator, out, 2,
        \\  (func ${[function_name]s} (param ${[input_local]s} (ref null $do_map))
        \\    (local $__gc_length i32)
        \\    (local $__map_index i32)
        \\    (local $__copy_bytes i32)
        \\    (local $__copy_bytes64 i64)
        \\    (local $__cabi_ptr i32)
        \\    (local $__memory_bytes i64)
        \\
    , .{ .function_name = config.function_name, .input_local = config.input_local });
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $len
        \\    local.set $__gc_length
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $keys
        \\    ref.as_non_null
        \\    array.len
        \\    local.get $__gc_length
        \\    i32.lt_u
        \\    if unreachable end
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $vals
        \\    ref.as_non_null
        \\    array.len
        \\    local.get $__gc_length
        \\    i32.lt_u
        \\    if unreachable end
        \\
    , .{ .input_local = config.input_local });
    try append_copy_byte_count(allocator, out, stride);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    i32.const 0
        \\    i32.const 0
        \\    i32.const {[alignment]d}
        \\    local.get $__copy_bytes
        \\
    , .{ .alignment = memory_plan.map_pair_alignment orelse return error.MeasuredElementAlignmentMissing });
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");
    try generated_text.append_fmt_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__map_index
        \\block $__map_copy_done
        \\  loop $__map_copy
        \\    local.get $__map_index
        \\    local.get $__gc_length
        \\    i32.ge_u
        \\    br_if $__map_copy_done
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[key_offset]d}
        \\    i32.add
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $keys
        \\    ref.as_non_null
        \\    local.get $__map_index
        \\    array.get $do_u32
        \\    i32.store
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[value_offset]d}
        \\    i32.add
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $vals
        \\    ref.as_non_null
        \\    local.get $__map_index
        \\    array.get $do_u32
        \\    i32.store
        \\    local.get $__map_index
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__map_index
        \\    br $__map_copy
        \\  end
        \\end
        \\local.get $__cabi_ptr
        \\local.get $__gc_length
        \\
    , .{ .input_local = config.input_local, .stride = stride, .key_offset = key_offset, .value_offset = value_offset });
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__cabi_ptr
        \\local.get $__copy_bytes
        \\i32.const {[alignment]d}
        \\i32.const 0
        \\
    , .{ .alignment = memory_plan.map_pair_alignment.? });
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    drop)\n");
}

fn emit_map_lift(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const value_kind = try validate_u32_key_map(plan, memory_plan);
    if (value_kind == .text) {
        return emit_map_lift_text(allocator, out, plan, memory_plan, config);
    }
    const pointer_offset = memory_plan.result_area_pointer_offset orelse return error.MeasuredResultAreaPointerMissing;
    const length_offset = memory_plan.result_area_length_offset orelse return error.MeasuredResultAreaLengthMissing;
    const key_offset = memory_plan.map_key_offset orelse return error.MeasuredMapFieldMissing;
    const value_offset = memory_plan.map_value_offset orelse return error.MeasuredMapFieldMissing;
    const stride = memory_plan.element_stride;

    try generated_text.append_fmt_block(allocator, out, 2,
        \\(func ${[function_name]s} (result (ref null $do_map))
        \\  (local $__result_area i32)
        \\  (local $__cabi_ptr i32)
        \\  (local $__gc_length i32)
        \\  (local $__map_index i32)
        \\  (local $__copy_bytes i32)
        \\  (local $__copy_bytes64 i64)
        \\  (local $__memory_bytes i64)
       \\  (local $__keys (ref $do_u32))
       \\  (local $__vals (ref $do_u32))
        \\
    , .{ .function_name = config.function_name });
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__result_area
        \\local.get $__result_area
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__result_area
        \\i32.const {[pointer_offset]d}
        \\i32.add
        \\i32.load
        \\local.set $__cabi_ptr
        \\local.get $__result_area
        \\i32.const {[length_offset]d}
        \\i32.add
        \\i32.load
        \\local.set $__gc_length
        \\
    , .{ .pointer_offset = pointer_offset, .length_offset = length_offset });
    try append_copy_byte_count(allocator, out, stride);
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__gc_length
        \\array.new_default $do_u32
        \\local.set $__keys
        \\local.get $__gc_length
        \\array.new_default $do_u32
        \\local.set $__vals
        \\i32.const 0
        \\local.set $__map_index
        \\block $__map_copy_done
        \\  loop $__map_copy
        \\    local.get $__map_index
        \\    local.get $__gc_length
        \\    i32.ge_u
        \\    br_if $__map_copy_done
        \\    local.get $__keys
        \\    local.get $__map_index
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[key_offset]d}
        \\    i32.add
        \\    i32.load
        \\    array.set $do_u32
        \\    local.get $__vals
        \\    local.get $__map_index
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[value_offset]d}
        \\    i32.add
        \\    i32.load
        \\    array.set $do_u32
        \\    local.get $__map_index
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__map_index
        \\    br $__map_copy
        \\  end
        \\end
        \\local.get $__cabi_ptr
        \\local.get $__copy_bytes
        \\i32.const {[alignment]d}
        \\i32.const 0
        \\
    , .{ .stride = stride, .key_offset = key_offset, .value_offset = value_offset, .alignment = memory_plan.map_pair_alignment.? });
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\drop
        \\local.get $__gc_length
        \\local.get $__keys
        \\local.get $__vals
        \\struct.new $do_map)
        \\
    );
}

fn emit_map_lower_text(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    _ = plan;
    const key_offset = memory_plan.map_key_offset orelse return error.MeasuredMapFieldMissing;
    const value_offset = memory_plan.map_value_offset orelse return error.MeasuredMapFieldMissing;
    const stride = memory_plan.element_stride;
    const alignment = memory_plan.map_pair_alignment orelse return error.MeasuredElementAlignmentMissing;

    try generated_text.append_fmt_block(allocator, out, 2,
        \\  (func ${[function_name]s} (param ${[input_local]s} (ref null $do_map))
        \\    (local $__gc_length i32)
        \\    (local $__map_index i32)
        \\    (local $__text_index i32)
        \\    (local $__text_length i32)
        \\    (local $__payload_offset i32)
        \\    (local $__payload_bytes i32)
        \\    (local $__payload_bytes64 i64)
        \\    (local $__copy_bytes i32)
        \\    (local $__copy_bytes64 i64)
        \\    (local $__total_bytes i32)
        \\    (local $__total_bytes64 i64)
        \\    (local $__cabi_ptr i32)
        \\    (local $__payload_ptr i32)
        \\    (local $__text_bytes (ref $do_bytes))
        \\    (local $__memory_bytes i64)
        \\
    , .{ .function_name = config.function_name, .input_local = config.input_local });

    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $len
        \\    local.set $__gc_length
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $keys
        \\    ref.as_non_null
        \\    array.len
        \\    local.get $__gc_length
        \\    i32.lt_u
        \\    if unreachable end
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $vals
        \\    ref.as_non_null
        \\    array.len
        \\    local.get $__gc_length
        \\    i32.lt_u
        \\    if unreachable end
        \\
    , .{ .input_local = config.input_local });

    // Measure all text payloads before allocating the canonical pair span.
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    i64.const 0
        \\    local.set $__payload_bytes64
        \\    i32.const 0
        \\    local.set $__map_index
        \\    block $__map_measure_done
        \\      loop $__map_measure
        \\        local.get $__map_index
        \\        local.get $__gc_length
        \\        i32.ge_u
        \\        br_if $__map_measure_done
        \\        local.get ${[input_local]s}
        \\        ref.as_non_null
        \\        struct.get $do_map $vals
        \\        ref.as_non_null
        \\        local.get $__map_index
        \\        array.get $do_text_array
        \\        ref.as_non_null
        \\        struct.get $do_text $length
        \\        local.set $__text_length
        \\        local.get ${[input_local]s}
        \\        ref.as_non_null
        \\        struct.get $do_map $vals
        \\        ref.as_non_null
        \\        local.get $__map_index
        \\        array.get $do_text_array
        \\        ref.as_non_null
        \\        struct.get $do_text $bytes
        \\        ref.as_non_null
        \\        array.len
        \\        local.get $__text_length
        \\        i32.lt_u
        \\        if unreachable end
        \\        local.get $__payload_bytes64
        \\        local.get $__text_length
        \\        i64.extend_i32_u
        \\        i64.add
        \\        local.tee $__payload_bytes64
        \\        i64.const 4294967295
        \\        i64.gt_u
        \\        if unreachable end
        \\        local.get $__map_index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $__map_index
        \\        br $__map_measure
        \\      end
        \\    end
        \\
    , .{ .input_local = config.input_local });

    try append_copy_byte_count(allocator, out, stride);
    try generated_text.append_block(allocator, out, 4,
        \\local.get $__copy_bytes64
        \\local.get $__payload_bytes64
        \\i64.add
        \\local.tee $__total_bytes64
        \\i64.const 4294967295
        \\i64.gt_u
        \\if unreachable end
        \\local.get $__total_bytes64
        \\i32.wrap_i64
        \\local.set $__total_bytes
        \\
    );
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    i32.const 0
        \\    i32.const 0
        \\    i32.const {[alignment]d}
        \\    local.get $__total_bytes
        \\
    , .{ .alignment = alignment });
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
    try emit_span_guard(allocator, out, "__cabi_ptr", "__total_bytes");
    try generated_text.append_fmt_block(allocator, out, 4,
        \\i32.const 0
        \\local.get $__copy_bytes
        \\i32.add
        \\local.set $__payload_offset
        \\i32.const 0
        \\local.set $__map_index
        \\block $__map_copy_done
        \\  loop $__map_copy
        \\    local.get $__map_index
        \\    local.get $__gc_length
        \\    i32.ge_u
        \\    br_if $__map_copy_done
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[key_offset]d}
        \\    i32.add
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $keys
        \\    ref.as_non_null
        \\    local.get $__map_index
        \\    array.get $do_u32
        \\    i32.store
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $vals
        \\    ref.as_non_null
        \\    local.get $__map_index
        \\    array.get $do_text_array
        \\    ref.as_non_null
        \\    struct.get $do_text $length
        \\    local.set $__text_length
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_map $vals
        \\    ref.as_non_null
        \\    local.get $__map_index
        \\    array.get $do_text_array
        \\    ref.as_non_null
        \\    struct.get $do_text $bytes
        \\    ref.as_non_null
        \\    local.set $__text_bytes
        \\    local.get $__cabi_ptr
        \\    local.get $__payload_offset
        \\    i32.add
        \\    local.tee $__payload_ptr
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[value_offset]d}
        \\    i32.add
        \\    i32.store
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[value_offset]d}
        \\    i32.add
        \\    i32.const 4
        \\    i32.add
        \\    local.get $__text_length
        \\    i32.store
        \\    i32.const 0
        \\    local.set $__text_index
        \\    block $__map_text_copy_done
        \\      loop $__map_text_copy
        \\        local.get $__text_index
        \\        local.get $__text_length
        \\        i32.ge_u
        \\        br_if $__map_text_copy_done
        \\        local.get $__payload_ptr
        \\        local.get $__text_index
        \\        i32.add
        \\        local.get $__text_bytes
        \\        local.get $__text_index
        \\        array.get_s $do_bytes
        \\        i32.store8
        \\        local.get $__text_index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $__text_index
        \\        br $__map_text_copy
        \\      end
        \\    end
        \\    local.get $__payload_offset
        \\    local.get $__text_length
        \\    i32.add
        \\    local.set $__payload_offset
        \\    local.get $__map_index
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__map_index
        \\    br $__map_copy
        \\  end
        \\end
        \\local.get $__cabi_ptr
        \\local.get $__gc_length
        \\
    , .{ .input_local = config.input_local, .stride = stride, .key_offset = key_offset, .value_offset = value_offset });
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__cabi_ptr
        \\local.get $__total_bytes
        \\i32.const {[alignment]d}
        \\i32.const 0
        \\
    , .{ .alignment = alignment });
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    drop)\n");
}

fn emit_map_lift_text(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    _ = plan;
    const pointer_offset = memory_plan.result_area_pointer_offset orelse return error.MeasuredResultAreaPointerMissing;
    const length_offset = memory_plan.result_area_length_offset orelse return error.MeasuredResultAreaLengthMissing;
    const key_offset = memory_plan.map_key_offset orelse return error.MeasuredMapFieldMissing;
    const value_offset = memory_plan.map_value_offset orelse return error.MeasuredMapFieldMissing;
    const stride = memory_plan.element_stride;
    const alignment = memory_plan.map_pair_alignment orelse return error.MeasuredElementAlignmentMissing;

    try generated_text.append_fmt_block(allocator, out, 2,
        \\(func ${[function_name]s} (result (ref null $do_map))
        \\  (local $__result_area i32)
        \\  (local $__cabi_ptr i32)
        \\  (local $__gc_length i32)
        \\  (local $__map_index i32)
        \\  (local $__text_index i32)
        \\  (local $__text_ptr i32)
        \\  (local $__text_length i32)
        \\  (local $__copy_bytes i32)
        \\  (local $__copy_bytes64 i64)
        \\  (local $__memory_bytes i64)
        \\  (local $__keys (ref $do_u32))
        \\  (local $__vals (ref $do_text_array))
        \\  (local $__text_bytes (ref $do_bytes))
        \\  (local $__text_result (ref $do_text))
        \\
    , .{ .function_name = config.function_name });
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__result_area
        \\local.get $__result_area
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__result_area
        \\i32.const {[pointer_offset]d}
        \\i32.add
        \\i32.load
        \\local.set $__cabi_ptr
        \\local.get $__result_area
        \\i32.const {[length_offset]d}
        \\i32.add
        \\i32.load
        \\local.set $__gc_length
        \\
    , .{ .pointer_offset = pointer_offset, .length_offset = length_offset });
    try append_copy_byte_count(allocator, out, stride);
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__gc_length
        \\array.new_default $do_u32
        \\local.set $__keys
        \\local.get $__gc_length
        \\array.new_default $do_text_array
        \\local.set $__vals
        \\i32.const 0
        \\local.set $__map_index
        \\block $__map_copy_done
        \\  loop $__map_copy
        \\    local.get $__map_index
        \\    local.get $__gc_length
        \\    i32.ge_u
        \\    br_if $__map_copy_done
        \\    local.get $__keys
        \\    local.get $__map_index
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[key_offset]d}
        \\    i32.add
        \\    i32.load
        \\    array.set $do_u32
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[value_offset]d}
        \\    i32.add
        \\    i32.load
        \\    local.set $__text_ptr
        \\    local.get $__cabi_ptr
        \\    local.get $__map_index
        \\    i32.const {[stride]d}
        \\    i32.mul
        \\    i32.add
        \\    i32.const {[value_offset]d}
        \\    i32.add
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.set $__text_length
        \\
    , .{ .stride = stride, .key_offset = key_offset, .value_offset = value_offset });
    try emit_span_guard(allocator, out, "__text_ptr", "__text_length");
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__text_length
        \\array.new_default $do_bytes
        \\local.set $__text_bytes
        \\i32.const 0
        \\local.set $__text_index
        \\block $__map_text_copy_done
        \\  loop $__map_text_copy
        \\    local.get $__text_index
        \\    local.get $__text_length
        \\    i32.ge_u
        \\    br_if $__map_text_copy_done
        \\    local.get $__text_bytes
        \\    local.get $__text_index
        \\    local.get $__text_ptr
        \\    local.get $__text_index
        \\    i32.add
        \\    i32.load8_u
        \\    array.set $do_bytes
        \\    local.get $__text_index
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__text_index
        \\    br $__map_text_copy
        \\  end
        \\end
        \\local.get $__text_length
        \\local.get $__text_bytes
        \\struct.new $do_text
        \\local.set $__text_result
        \\local.get $__vals
        \\local.get $__map_index
        \\local.get $__text_result
        \\array.set $do_text_array
        \\local.get $__map_index
        \\i32.const 1
        \\i32.add
        \\local.set $__map_index
        \\br $__map_copy
        \\  end
        \\end
        \\local.get $__cabi_ptr
        \\local.get $__copy_bytes
        \\i32.const {[alignment]d}
        \\i32.const 0
        \\
    , .{ .alignment = alignment });
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\drop
        \\local.get $__gc_length
        \\local.get $__keys
        \\local.get $__vals
        \\struct.new $do_map)
        \\
    );
}

fn validate_u32_key_map(
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
) !MapValueKind {
    if (plan.root.kind != .map or plan.root.children.len != 2) return error.UnsupportedMarshalShape;
    const key = &plan.root.children[0];
    if (key.kind != .scalar or key.scalar_kind != .u32) return error.UnsupportedMarshalShape;
    const value = &plan.root.children[1];
    const value_kind: MapValueKind = switch (value.kind) {
        .scalar => if (value.scalar_kind == .u32) .u32 else return error.UnsupportedMarshalShape,
        .text => .text,
        else => return error.UnsupportedMarshalShape,
    };
    const pair_size: u32 = switch (value_kind) {
        .u32 => 8,
        .text => 12,
    };
    if (memory_plan.copy_shape != .map_entries or memory_plan.element_stride != pair_size or
        memory_plan.map_pair_byte_size != pair_size or memory_plan.map_pair_alignment != 4 or
        memory_plan.map_key_offset != 0 or memory_plan.map_value_offset != 4)
    {
        return error.UnsupportedMarshalShape;
    }

    const key_facts = key.measured orelse return error.MeasuredChildMissing;
    if (key_facts.offset != 0 or key_facts.byte_size != 4 or key_facts.alignment != 4 or key_facts.core_type != .i32) {
        return error.UnsupportedMarshalShape;
    }
    const value_facts = value.measured orelse return error.MeasuredChildMissing;
    switch (value_kind) {
        .u32 => {
            if (value_facts.offset != 4 or value_facts.byte_size != 4 or value_facts.alignment != 4 or value_facts.core_type != .i32) {
                return error.UnsupportedMarshalShape;
            }
        },
        .text => {
            if (value_facts.offset != 4 or value_facts.byte_size != 8 or value_facts.alignment != 4 or
                value_facts.pointer_offset != 0 or value_facts.length_offset != 4)
            {
                return error.UnsupportedMarshalShape;
            }
        },
    }
    return value_kind;
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

    if (memory_plan.record_mixed_text_two_u32_lists_lift) {
        try emit_record_lift_mixed_text_two_u32_lists(allocator, out, plan, config);
        return;
    }

    const has_record_list = marshal_ops.record_contains_list(&plan.root);
    const has_record_u32_list = marshal_ops.record_contains_u32_list(&plan.root);
    const has_record_byte_list = marshal_ops.record_contains_byte_list(&plan.root);
    try append_fmt(allocator, out, "  (func ${[function_name]s} (result (ref null ", .{ .function_name = config.function_name });
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try generated_text.append_block(allocator, out, 0,
        \\))
        \\    (local $__result_area i32)
        \\    (local $__record_bytes i32)
        \\    (local $__memory_bytes i64)
        \\    (local $__text_ptr i32)
        \\    (local $__text_length i32)
        \\    (local $__text_index i32)
        \\    (local $__text_bytes (ref $do_bytes))
        \\
    );
    if (has_record_list) {
        try generated_text.append_block(allocator, out, 4,
            \\(local $__list_ptr i32)
            \\(local $__list_length i32)
            \\(local $__list_index i32)
            \\(local $__list_copy_bytes i32)
            \\(local $__list_copy_bytes64 i64)
            \\
        );
        if (has_record_u32_list) {
            try out.appendSlice(allocator, "    (local $__list_array (ref $do_u32))\n");
        }
        if (has_record_byte_list) {
            try out.appendSlice(allocator, "    (local $__byte_list_array (ref $do_bytes))\n");
        }
    }
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__result_area
        \\local.get $__result_area
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    i32.const {[byte_size]d}
        \\    local.set $__record_bytes
        \\
    , .{ .byte_size = measured.byte_size });
    try emit_span_guard(allocator, out, "__result_area", "__record_bytes");

    try emit_record_lift_value(allocator, out, &plan.root, 0, true, config.realloc_name);
    try out.appendSlice(allocator, "    struct.new ");
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try out.appendSlice(allocator, ")\n");
}

fn emit_record_lift_mixed_text_two_u32_lists(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    config: EmitConfig,
) !void {
    if (!marshal_ops.record_is_mixed_text_two_u32_lists_lift(&plan.root)) {
        return error.UnsupportedMarshalShape;
    }
    const root = &plan.root;
    const label = root.children[1].measured orelse return error.MeasuredChildMissing;
    const first = root.children[2].measured orelse return error.MeasuredChildMissing;
    const second = root.children[3].measured orelse return error.MeasuredChildMissing;
    const label_pointer = label.offset + (label.pointer_offset orelse return error.MeasuredResultAreaPointerMissing);
    const label_length = label.offset + (label.length_offset orelse return error.MeasuredResultAreaLengthMissing);
    const first_pointer = first.offset + (first.pointer_offset orelse return error.MeasuredResultAreaPointerMissing);
    const first_length = first.offset + (first.length_offset orelse return error.MeasuredResultAreaLengthMissing);
    const second_pointer = second.offset + (second.pointer_offset orelse return error.MeasuredResultAreaPointerMissing);
    const second_length = second.offset + (second.length_offset orelse return error.MeasuredResultAreaLengthMissing);

    try append_fmt(allocator, out, "  (func ${[function_name]s} (result (ref null ", .{ .function_name = config.function_name });
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try generated_text.append_block(allocator, out, 0,
        \\))
        \\    (local $__result_area i32)
        \\    (local $__record_bytes i32)
        \\    (local $__gc_code i32)
        \\    (local $__cabi_ptr_0 i32)
        \\    (local $__gc_length_0 i32)
        \\    (local $__gc_index_0 i32)
        \\    (local $__gc_values_0 (ref $do_bytes))
        \\    (local $__cabi_ptr_1 i32)
        \\    (local $__gc_length_1 i32)
        \\    (local $__gc_index_1 i32)
        \\    (local $__gc_copy_bytes_1 i32)
        \\    (local $__gc_copy_bytes64_1 i64)
        \\    (local $__gc_values_1 (ref $do_u32))
        \\    (local $__cabi_ptr_2 i32)
        \\    (local $__gc_length_2 i32)
        \\    (local $__gc_index_2 i32)
        \\    (local $__gc_copy_bytes_2 i32)
        \\    (local $__gc_copy_bytes64_2 i64)
        \\    (local $__gc_values_2 (ref $do_u32))
        \\    (local $__gc_label (ref null $do_text))
        \\    (local $__gc_first (ref null $do_u32))
        \\    (local $__gc_second (ref null $do_u32))
        \\    (local $__memory_bytes i64)
        \\    (local $__gc_alloc_mask i32)
        \\    (local $__gc_cleanup_trap i32)
        \\
    );
    try out.appendSlice(allocator, "    (local $__gc_result (ref null ");
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try out.appendSlice(allocator, "))\n");
    try out.appendSlice(allocator, "    block $__text_two_lists_lift_cleanup\n");

    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__result_area
        \\i32.const 28
        \\local.set $__record_bytes
        \\i32.const 0
        \\local.set $__gc_cleanup_trap
        \\local.get $__result_area
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try emit_span_guard(allocator, out, "__result_area", "__record_bytes");
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__result_area
        \\i32.const 0
        \\i32.add
        \\i32.load
        \\local.set $__gc_code
        \\local.get $__result_area
        \\i32.const {[label_pointer]d}
        \\i32.add
        \\i32.load
        \\local.set $__cabi_ptr_0
        \\local.get $__result_area
        \\i32.const {[label_length]d}
        \\i32.add
        \\i32.load
        \\local.set $__gc_length_0
        \\local.get $__result_area
        \\i32.const {[first_pointer]d}
        \\i32.add
        \\i32.load
        \\local.set $__cabi_ptr_1
        \\local.get $__result_area
        \\i32.const {[first_length]d}
        \\i32.add
        \\i32.load
        \\local.set $__gc_length_1
        \\local.get $__result_area
        \\i32.const {[second_pointer]d}
        \\i32.add
        \\i32.load
        \\local.set $__cabi_ptr_2
        \\local.get $__result_area
        \\i32.const {[second_length]d}
        \\i32.add
        \\i32.load
        \\local.set $__gc_length_2
        \\i32.const 7
        \\local.set $__gc_alloc_mask
        \\
    , .{
        .label_pointer = label_pointer,
        .label_length = label_length,
        .first_pointer = first_pointer,
        .first_length = first_length,
        .second_pointer = second_pointer,
        .second_length = second_length,
    });

    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_0", "__gc_length_0", "__text_two_lists_lift_cleanup");
    try generated_text.append_block(allocator, out, 4,
        \\local.get $__gc_length_1
        \\i32.const 3
        \\i32.gt_u
        \\
    );
    try emit_trap_guard_branch_to_cleanup(allocator, out, "__text_two_lists_lift_cleanup");
    try append_copy_byte_count_branch_to_cleanup(
        allocator,
        out,
        "__gc_length_1",
        "__gc_copy_bytes_1",
        "__gc_copy_bytes64_1",
        4,
        "__text_two_lists_lift_cleanup",
    );
    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_1", "__gc_copy_bytes_1", "__text_two_lists_lift_cleanup");

    try generated_text.append_block(allocator, out, 4,
        \\local.get $__gc_length_2
        \\i32.const 2
        \\i32.gt_u
        \\
    );
    try emit_trap_guard_branch_to_cleanup(allocator, out, "__text_two_lists_lift_cleanup");
    try append_copy_byte_count_branch_to_cleanup(
        allocator,
        out,
        "__gc_length_2",
        "__gc_copy_bytes_2",
        "__gc_copy_bytes64_2",
        4,
        "__text_two_lists_lift_cleanup",
    );
    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_2", "__gc_copy_bytes_2", "__text_two_lists_lift_cleanup");

    try generated_text.append_block(allocator, out, 4,
        \\local.get $__gc_length_0
        \\array.new_default $do_bytes
        \\local.set $__gc_values_0
        \\i32.const 0
        \\local.set $__gc_index_0
        \\block $__text_two_lists_lift_label_copy_done
        \\  loop $__text_two_lists_lift_label_copy
        \\    local.get $__gc_index_0
        \\    local.get $__gc_length_0
        \\    i32.ge_u
        \\    br_if $__text_two_lists_lift_label_copy_done
        \\    local.get $__gc_values_0
        \\    local.get $__gc_index_0
        \\    local.get $__cabi_ptr_0
        \\    local.get $__gc_index_0
        \\    i32.add
        \\    i32.load8_u
        \\    array.set $do_bytes
        \\    local.get $__gc_index_0
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__gc_index_0
        \\    br $__text_two_lists_lift_label_copy
        \\  end
        \\end
        \\local.get $__gc_length_0
        \\local.get $__gc_values_0
        \\struct.new $do_text
        \\local.set $__gc_label
        \\
    );
    try emit_lift_u32_array_copy(allocator, out, 1, "__text_two_lists_lift", "__cabi_ptr_1", "__gc_length_1", "__gc_values_1");
    try emit_lift_u32_array_copy(allocator, out, 2, "__text_two_lists_lift", "__cabi_ptr_2", "__gc_length_2", "__gc_values_2");

    try generated_text.append_block(allocator, out, 4,
        \\local.get $__gc_code
        \\local.get $__gc_label
        \\local.get $__gc_values_1
        \\local.get $__gc_values_2
        \\
    );
    try out.appendSlice(allocator, "        struct.new ");
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try out.appendSlice(allocator, "\n        local.set $__gc_result\n    end\n");
    try emit_conditional_cleanup(allocator, out, 4, .{
        .pointer_local = "__cabi_ptr_2",
        .length_local = "__gc_length_2",
        .size_local = "__gc_copy_bytes_2",
        .alignment = 4,
    }, config.realloc_name);
    try emit_conditional_cleanup(allocator, out, 2, .{
        .pointer_local = "__cabi_ptr_1",
        .length_local = "__gc_length_1",
        .size_local = "__gc_copy_bytes_1",
        .alignment = 4,
    }, config.realloc_name);
    try emit_conditional_cleanup(allocator, out, 1, .{
        .pointer_local = "__cabi_ptr_0",
        .length_local = "__gc_length_0",
        .alignment = 1,
    }, config.realloc_name);
    try generated_text.append_block(allocator, out, 0,
        \\    local.get $__gc_cleanup_trap
        \\    if unreachable end
        \\    local.get $__gc_result
        \\)
        \\
    );
}

fn emit_lift_u32_array_copy(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    slot: u32,
    label_prefix: []const u8,
    pointer_local: []const u8,
    length_local: []const u8,
    array_local: []const u8,
) !void {
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get ${[length_local]s}
        \\array.new_default $do_u32
        \\local.set ${[array_local]s}
        \\i32.const 0
        \\local.set $__gc_index_{[slot]d}
        \\block ${[label_prefix]s}_u32_copy_done_{[slot]d}
        \\  loop ${[label_prefix]s}_u32_copy_{[slot]d}
        \\    local.get $__gc_index_{[slot]d}
        \\    local.get ${[length_local]s}
        \\    i32.ge_u
        \\    br_if ${[label_prefix]s}_u32_copy_done_{[slot]d}
        \\    local.get ${[array_local]s}
        \\    local.get $__gc_index_{[slot]d}
        \\    local.get ${[pointer_local]s}
        \\    local.get $__gc_index_{[slot]d}
        \\    i32.const 4
        \\    i32.mul
        \\    i32.add
        \\    i32.load
        \\    array.set $do_u32
        \\    local.get $__gc_index_{[slot]d}
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__gc_index_{[slot]d}
        \\    br ${[label_prefix]s}_u32_copy_{[slot]d}
        \\  end
        \\end
        \\
    , .{
        .slot = slot,
        .label_prefix = label_prefix,
        .pointer_local = pointer_local,
        .length_local = length_local,
        .array_local = array_local,
    });
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
            try generated_text.append_fmt_block(allocator, out, 4,
                \\    local.get $__result_area
                \\    i32.const {[offset]d}
                \\    i32.add
                \\    {[load_name]s}
                \\
            , .{ .offset = offset, .load_name = load_name });
        },
        .text => {
            const facts = node.measured orelse return error.MeasuredChildMissing;
            const pointer_offset = facts.pointer_offset orelse return error.MeasuredResultAreaPointerMissing;
            const length_offset = facts.length_offset orelse return error.MeasuredResultAreaLengthMissing;
            const field_offset = std.math.add(u32, base_offset, facts.offset) catch return error.OffsetOverflow;
            const pointer = std.math.add(u32, field_offset, pointer_offset) catch return error.OffsetOverflow;
            const length = std.math.add(u32, field_offset, length_offset) catch return error.OffsetOverflow;
            try generated_text.append_fmt_block(allocator, out, 4,
                \\    local.get $__result_area
                \\    i32.const {[pointer]d}
                \\    i32.add
                \\    i32.load
                \\    local.set $__text_ptr
                \\    local.get $__result_area
                \\    i32.const {[length]d}
                \\    i32.add
                \\    i32.load
                \\    local.set $__text_length
                \\
            , .{ .pointer = pointer, .length = length });
            try emit_span_guard(allocator, out, "__text_ptr", "__text_length");
            try generated_text.append_fmt_block(allocator, out, 4,
                \\    local.get $__text_length
                \\    array.new_default $do_bytes
                \\    local.set $__text_bytes
                \\    i32.const 0
                \\    local.set $__text_index
                \\    block $__text_copy_done
                \\      loop $__text_copy
                \\        local.get $__text_index
                \\        local.get $__text_length
                \\        i32.ge_u
                \\        br_if $__text_copy_done
                \\        local.get $__text_bytes
                \\        local.get $__text_index
                \\        local.get $__text_ptr
                \\        local.get $__text_index
                \\        i32.add
                \\        i32.load8_u
                \\        array.set $do_bytes
                \\        local.get $__text_index
                \\        i32.const 1
                \\        i32.add
                \\        local.set $__text_index
                \\        br $__text_copy
                \\      end
                \\    end
                \\    local.get $__text_ptr
                \\    local.get $__text_length
                \\    i32.const 1
                \\    i32.const 0
                \\    call ${[realloc_name]s}
                \\    drop
                \\    local.get $__text_length
                \\    local.get $__text_bytes
                \\    struct.new $do_text
                \\
            , .{ .realloc_name = realloc_name });
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
            try generated_text.append_fmt_block(allocator, out, 4,
                \\    local.get $__result_area
                \\    i32.const {[pointer]d}
                \\    i32.add
                \\    i32.load
                \\    local.set $__list_ptr
                \\    local.get $__result_area
                \\    i32.const {[length]d}
                \\    i32.add
                \\    i32.load
                \\    local.set $__list_length
                \\
            , .{ .pointer = pointer, .length = length });
            try generated_text.append_fmt_block(allocator, out, 4,
                \\    local.get $__list_length
                \\    i64.extend_i32_u
                \\    i64.const {[stride]d}
                \\    i64.mul
                \\    local.tee $__list_copy_bytes64
                \\    i64.const 4294967295
                \\    i64.gt_u
                \\    if unreachable end
                \\    local.get $__list_copy_bytes64
                \\    i32.wrap_i64
                \\    local.set $__list_copy_bytes
                \\
            , .{ .stride = stride });
            try emit_span_guard(allocator, out, "__list_ptr", "__list_copy_bytes");
            try generated_text.append_fmt_block(allocator, out, 4,
                \\    local.get $__list_length
                \\    array.new_default {[array_type]s}
                \\    local.set ${[array_local]s}
                \\    i32.const 0
                \\    local.set $__list_index
                \\    block $__list_copy_done
                \\      loop $__list_copy
                \\        local.get $__list_index
                \\        local.get $__list_length
                \\        i32.ge_u
                \\        br_if $__list_copy_done
                \\        local.get ${[array_local]s}
                \\        local.get $__list_index
                \\        local.get $__list_ptr
                \\        local.get $__list_index
                \\        i32.const {[stride]d}
                \\        i32.mul
                \\        i32.add
                \\        {[load_instruction]s}
                \\        array.set {[array_type]s}
                \\        local.get $__list_index
                \\        i32.const 1
                \\        i32.add
                \\        local.set $__list_index
                \\        br $__list_copy
                \\      end
                \\    end
                \\
            , .{
                .array_type = array_type,
                .array_local = array_local,
                .stride = stride,
                .load_instruction = if (is_byte_list) "i32.load8_u" else "i32.load",
            });
            try generated_text.append_fmt_block(allocator, out, 4,
                \\    local.get $__list_ptr
                \\    local.get $__list_copy_bytes
                \\    i32.const {[stride]d}
                \\    i32.const 0
                \\    call ${[realloc_name]s}
                \\    drop
                \\    local.get ${[array_local]s}
                \\
            , .{ .stride = stride, .realloc_name = realloc_name, .array_local = array_local });
        },
        .map => return error.UnsupportedMarshalShape,
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
            try append_fmt(allocator, out, "    struct.new $do_{[name]s}\n", .{ .name = name });
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

    try append_fmt(allocator, out, "  (func ${[function_name]s} (param ${[input_local]s} (ref null ", .{ .function_name = config.function_name, .input_local = config.input_local });
    try append_lowercase_wat_name(allocator, out, config.root_type_name);
    try out.appendSlice(allocator, "))\n");

    if (memory_plan.record_managed_text_scalar_list_pair_lower) {
        try emit_record_lower_managed_text_scalar_list_pair(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_managed_text_byte_u32_list_lower) {
        try emit_record_lower_managed_text_byte_u32_list(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_managed_scalar_list_pair_lower) {
        try emit_record_lower_managed_scalar_list_pair(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_managed_mixed_scalar_list_lower) {
        try emit_record_lower_managed_mixed_scalar_list(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_managed_text_lower) {
        try emit_record_lower_managed_text(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_managed_scalar_list_lower) {
        try emit_record_lower_managed_scalar_list(allocator, out, plan, memory_plan, config);
        return;
    }

    if (memory_plan.record_indirect != null) {
        try generated_text.append_block(allocator, out, 4,
            \\(local $__cabi_ptr i32)
            \\(local $__record_bytes i32)
            \\(local $__memory_bytes i64)
            \\i32.const 0
            \\i32.const 0
            \\
        );
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    i32.const {[alignment]d}
            \\    i32.const {[byte_size]d}
            \\
        , .{ .alignment = measured.alignment, .byte_size = measured.byte_size });
        try append_named_call(allocator, out, config.realloc_name);
        try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
        try out.appendSlice(allocator, "    i32.const ");
        try generated_text.append_fmt_block(allocator, out, 0,
            \\{[byte_size]d}
            \\    local.set $__record_bytes
            \\
        , .{ .byte_size = measured.byte_size });
        try emit_span_guard(allocator, out, "__cabi_ptr", "__record_bytes");

        var path = std.ArrayList(RecordPathSegment).empty;
        defer path.deinit(allocator);
        try emit_record_lower_fields(allocator, out, &plan.root, 0, true, config.input_local, config.root_type_name, &path);

        try out.appendSlice(allocator, "    local.get $__cabi_ptr\n");
        try append_named_call(allocator, out, config.canonical_call_name);
        try out.appendSlice(allocator, "    local.get $__cabi_ptr\n");
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    i32.const {[byte_size]d}
            \\    i32.const {[alignment]d}
            \\    i32.const 0
            \\
        , .{ .byte_size = measured.byte_size, .alignment = measured.alignment });
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
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    (local $__gc_length_{[slot]d} i32)
            \\    (local $__gc_index_{[slot]d} i32)
            \\    (local $__cabi_ptr_{[slot]d} i32)
            \\
        , .{ .slot = slot });
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
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    local.set $__gc_length_{[slot]d}
            \\
        , .{ .slot = slot });

        try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    ref.as_non_null
            \\    struct.get $do_text $bytes
            \\    ref.as_non_null
            \\    array.len
            \\    local.get $__gc_length_{[slot]d}
            \\    i32.lt_u
            \\    if unreachable end
            \\    i32.const 0
            \\    i32.const 0
            \\    i32.const 1
            \\    local.get $__gc_length_{[slot]d}
            \\
        , .{ .slot = slot });
        try append_named_call(allocator, out, config.realloc_name);
        try append_fmt(allocator, out, "    local.set $__cabi_ptr_{[slot]d}\n", .{ .slot = slot });
        const pointer_local = try generated_text.alloc_fmt(allocator, "__cabi_ptr_{[slot]d}", .{ .slot = slot });
        defer allocator.free(pointer_local);
        const length_local = try generated_text.alloc_fmt(allocator, "__gc_length_{[slot]d}", .{ .slot = slot });
        defer allocator.free(length_local);
        try emit_span_guard(allocator, out, pointer_local, length_local);
        try generated_text.append_fmt_block(
            allocator,
            out,
            4,
            \\    i32.const 0
            \\    local.set $__gc_index_{[slot]d}
            \\    block $__copy_done_{[slot]d}
            \\      loop $__copy_{[slot]d}
            \\        local.get $__gc_index_{[slot]d}
            \\        local.get $__gc_length_{[slot]d}
            \\        i32.ge_u
            \\        br_if $__copy_done_{[slot]d}
            \\        local.get $__cabi_ptr_{[slot]d}
            \\        local.get $__gc_index_{[slot]d}
            \\        i32.add
            \\
        ,
            .{ .slot = slot },
        );
        try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
        try generated_text.append_fmt_block(allocator, out, 8,
            \\        ref.as_non_null
            \\        struct.get $do_text $bytes
            \\        ref.as_non_null
            \\        local.get $__gc_index_{[slot]d}
            \\        array.get_s $do_bytes
            \\        i32.store8
            \\        local.get $__gc_index_{[slot]d}
            \\        i32.const 1
            \\        i32.add
            \\        local.set $__gc_index_{[slot]d}
            \\        br $__copy_{[slot]d}
            \\      end
            \\    end
            \\
        , .{ .slot = slot });
    }

    var code_path = std.ArrayList(RecordPathSegment).empty;
    defer code_path.deinit(allocator);
    try code_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 0 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, code_path.items);
    for (0..field_count) |slot| {
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get $__cabi_ptr_{[slot]d}
            \\    local.get $__gc_length_{[slot]d}
            \\
        , .{ .slot = slot });
    }
    try append_named_call(allocator, out, config.canonical_call_name);

    var free_slot = field_count;
    while (free_slot > 0) {
        free_slot -= 1;
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get $__cabi_ptr_{[slot]d}
            \\    local.get $__gc_length_{[slot]d}
            \\    i32.const 1
            \\    i32.const 0
            \\
        , .{ .slot = free_slot });
        try append_named_call(allocator, out, config.realloc_name);
        try out.appendSlice(allocator, "    drop\n");
    }
    try out.appendSlice(allocator, ")\n");
}

fn emit_record_lower_managed_mixed_scalar_list(
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
    const mixed = memory_plan.managed_mixed_scalar_list_lower orelse return error.UnsupportedMarshalShape;
    if (mixed.text.field_index != 1 or mixed.scalar_list.field_index != 2 or
        mixed.text.pointer_offset != 0 or mixed.text.length_offset != 4 or
        mixed.scalar_list.pointer_offset != 0 or mixed.scalar_list.length_offset != 4 or
        mixed.scalar_list.capacity == 0)
    {
        return error.UnsupportedMarshalShape;
    }
    if (root.children[0].kind != .scalar or root.children[0].scalar_kind != .u32 or
        root.children[1].kind != .text or root.children[2].kind != .list or
        root.children[2].children.len != 1 or root.children[2].children[0].kind != .scalar or
        (root.children[2].children[0].scalar_kind != .u8 and
            root.children[2].children[0].scalar_kind != .u32))
    {
        return error.UnsupportedMarshalShape;
    }
    const element = &root.children[2].children[0];
    const expected_stride: u32 = switch (mixed.scalar_list.element_kind) {
        .byte => 1,
        .u32 => 4,
    };
    if (mixed.scalar_list.element_byte_size != expected_stride or
        mixed.scalar_list.element_alignment != expected_stride or
        mixed.scalar_list.element_stride != expected_stride)
    {
        return error.UnsupportedMarshalShape;
    }
    switch (mixed.scalar_list.element_kind) {
        .byte => if (element.scalar_kind != .u8) return error.UnsupportedMarshalShape,
        .u32 => if (element.scalar_kind != .u32) return error.UnsupportedMarshalShape,
    }
    const element_facts = element.measured orelse return error.MeasuredChildMissing;
    if (element_facts.byte_size != expected_stride or element_facts.alignment != expected_stride or
        (mixed.scalar_list.element_kind == .byte and element_facts.core_type != null) or
        (mixed.scalar_list.element_kind == .u32 and element_facts.core_type != .i32))
    {
        return error.UnsupportedMarshalShape;
    }
    const array_type = scalar_list_gc_type(mixed.scalar_list.element_kind);
    const load_instruction = scalar_list_load_instruction(mixed.scalar_list.element_kind);
    const store_instruction = scalar_list_store_instruction(mixed.scalar_list.element_kind);
    const payload_span_local = if (mixed.scalar_list.element_stride == 1)
        "__gc_length_1"
    else
        "__gc_copy_bytes_1";

    try generated_text.append_fmt_block(allocator, out, 4,
        \\(local $__gc_length_0 i32)
        \\(local $__gc_index_0 i32)
        \\(local $__cabi_ptr_0 i32)
        \\(local $__gc_values_0 (ref $do_bytes))
        \\(local $__gc_length_1 i32)
        \\(local $__gc_index_1 i32)
        \\(local $__cabi_ptr_1 i32)
        \\(local $__gc_values_1 (ref {[array_type]s}))
        \\(local $__gc_copy_bytes_1 i32)
        \\(local $__gc_copy_bytes64_1 i64)
        \\(local $__memory_bytes i64)
        \\(local $__gc_alloc_mask i32)
        \\(local $__gc_cleanup_trap i32)
        \\block $__mixed_cleanup
        \\
    , .{ .array_type = array_type });

    var text_path = std.ArrayList(RecordPathSegment).empty;
    defer text_path.deinit(allocator);
    try text_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 1 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\ref.as_non_null
        \\struct.get $do_text $length
        \\local.set $__gc_length_0
        \\
    );
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\ref.as_non_null
        \\struct.get $do_text $bytes
        \\ref.as_non_null
        \\local.set $__gc_values_0
        \\local.get $__gc_values_0
        \\array.len
        \\local.get $__gc_length_0
        \\i32.lt_u
        \\if unreachable end
        \\i32.const 0
        \\i32.const 0
        \\i32.const 1
        \\local.get $__gc_length_0
        \\
    );
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\local.set $__cabi_ptr_0
        \\i32.const 1
        \\local.set $__gc_alloc_mask
        \\
    );
    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_0", "__gc_length_0", "__mixed_cleanup");
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__gc_index_0
        \\block $__mixed_text_copy_done
        \\  loop $__mixed_text_copy
        \\    local.get $__gc_index_0
        \\    local.get $__gc_length_0
        \\    i32.ge_u
        \\    br_if $__mixed_text_copy_done
        \\    local.get $__cabi_ptr_0
        \\    local.get $__gc_index_0
        \\    i32.add
        \\    local.get $__gc_values_0
        \\    local.get $__gc_index_0
        \\    array.get_s $do_bytes
        \\    i32.store8
        \\    local.get $__gc_index_0
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__gc_index_0
        \\    br $__mixed_text_copy
        \\  end
        \\end
        \\
    );

    var payload_path = std.ArrayList(RecordPathSegment).empty;
    defer payload_path.deinit(allocator);
    try payload_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 2 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, payload_path.items);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\ref.as_non_null
        \\local.set $__gc_values_1
        \\local.get $__gc_values_1
        \\array.len
        \\local.set $__gc_length_1
        \\local.get $__gc_length_1
        \\i32.const {[capacity]d}
        \\i32.gt_u
        \\
    , .{ .capacity = mixed.scalar_list.capacity });
    try emit_trap_guard_branch_to_cleanup(allocator, out, "__mixed_cleanup");
    try append_copy_byte_count_for_locals(
        allocator,
        out,
        "__gc_length_1",
        "__gc_copy_bytes_1",
        "__gc_copy_bytes64_1",
        mixed.scalar_list.element_stride,
    );
    try generated_text.append_fmt_block(allocator, out, 4,
        \\i32.const 0
        \\i32.const 0
        \\i32.const {[alignment]d}
        \\local.get $__gc_copy_bytes_1
        \\
    , .{ .alignment = mixed.scalar_list.element_alignment });
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\local.set $__cabi_ptr_1
        \\i32.const 3
        \\local.set $__gc_alloc_mask
        \\
    );
    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_1", payload_span_local, "__mixed_cleanup");
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__gc_index_1
        \\block $__mixed_payload_copy_done
        \\  loop $__mixed_payload_copy
        \\    local.get $__gc_index_1
        \\    local.get $__gc_length_1
        \\    i32.ge_u
        \\    br_if $__mixed_payload_copy_done
        \\    local.get $__cabi_ptr_1
        \\
    );
    if (mixed.scalar_list.element_stride == 1) {
        try generated_text.append_block(allocator, out, 8,
            \\    local.get $__gc_index_1
            \\    i32.add
            \\
        );
    } else {
        try generated_text.append_fmt_block(allocator, out, 8,
            \\    local.get $__gc_index_1
            \\    i32.const {[stride]d}
            \\    i32.mul
            \\    i32.add
            \\
        , .{ .stride = mixed.scalar_list.element_stride });
    }
    try generated_text.append_block(allocator, out, 8,
        \\    local.get $__gc_values_1
        \\    local.get $__gc_index_1
        \\
    );
    try generated_text.append_fmt_block(allocator, out, 8,
        \\    {[load]s}
        \\    {[store]s}
        \\
    , .{ .load = load_instruction, .store = store_instruction });
    try generated_text.append_block(allocator, out, 8,
        \\    local.get $__gc_index_1
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__gc_index_1
        \\    br $__mixed_payload_copy
        \\  end
        \\end
        \\
    );

    var code_path = std.ArrayList(RecordPathSegment).empty;
    defer code_path.deinit(allocator);
    try code_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 0 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, code_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\local.get $__cabi_ptr_0
        \\local.get $__gc_length_0
        \\local.get $__cabi_ptr_1
        \\local.get $__gc_length_1
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try out.appendSlice(allocator, "    end\n");
    try emit_conditional_cleanup(allocator, out, 2, .{
        .pointer_local = "__cabi_ptr_1",
        .length_local = "__gc_length_1",
        .size_local = if (mixed.scalar_list.element_stride == 1) null else "__gc_copy_bytes_1",
        .alignment = mixed.scalar_list.element_alignment,
    }, config.realloc_name);
    try emit_conditional_cleanup(allocator, out, 1, .{
        .pointer_local = "__cabi_ptr_0",
        .length_local = "__gc_length_0",
    }, config.realloc_name);
    try generated_text.append_block(allocator, out, 0,
        \\    local.get $__gc_cleanup_trap
        \\    if unreachable end
        \\)
        \\
    );
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

fn emit_record_lower_managed_text_scalar_list_pair(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const mixed = memory_plan.managed_text_scalar_list_pair_lower orelse return error.UnsupportedMarshalShape;
    try emit_record_lower_managed_text_scalar_list_pair_impl(allocator, out, plan, memory_plan, config, mixed);
}

fn emit_record_lower_managed_text_byte_u32_list(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const mixed = memory_plan.managed_text_byte_u32_list_lower orelse return error.UnsupportedMarshalShape;
    try emit_record_lower_managed_text_scalar_list_pair_impl(allocator, out, plan, memory_plan, config, .{
        .text = mixed.text,
        .first = mixed.bytes,
        .second = mixed.values,
    });
}

fn emit_record_lower_managed_text_scalar_list_pair_impl(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
    mixed: marshal_ops.ManagedTextScalarListPairLower,
) !void {
    const root = &plan.root;
    if (root.kind != .record or root.children.len != memory_plan.record_field_count or root.children.len != 4) {
        return error.UnsupportedMarshalShape;
    }
    if (mixed.text.field_index != 1 or mixed.text.pointer_offset != 0 or mixed.text.length_offset != 4) {
        return error.UnsupportedMarshalShape;
    }
    if (root.children[0].kind != .scalar or root.children[0].scalar_kind != .u32 or
        root.children[1].kind != .text)
    {
        return error.UnsupportedMarshalShape;
    }
    const fields = [_]marshal_ops.ManagedScalarListField{ mixed.first, mixed.second };
    for (fields, 0..) |field, slot| {
        if (field.field_index != slot + 2 or field.pointer_offset != 0 or field.length_offset != 4 or
            field.capacity == 0)
        {
            return error.UnsupportedMarshalShape;
        }
        const payload = &root.children[field.field_index];
        if (payload.kind != .list or payload.children.len != 1) return error.UnsupportedMarshalShape;
        const element = &payload.children[0];
        if (element.kind != .scalar) return error.UnsupportedMarshalShape;
        const element_facts = element.measured orelse return error.MeasuredChildMissing;
        const expected_size: u32 = switch (field.element_kind) {
            .byte => 1,
            .u32 => 4,
        };
        const expected_scalar = switch (field.element_kind) {
            .byte => wit_abi_types.ScalarKind.u8,
            .u32 => wit_abi_types.ScalarKind.u32,
        };
        const scalar_kind = element.scalar_kind orelse return error.UnsupportedMarshalShape;
        if (scalar_kind != expected_scalar or element_facts.byte_size != expected_size or
            element_facts.alignment != expected_size or
            (field.element_kind == .u32 and element_facts.core_type != .i32) or
            (field.element_kind == .byte and element_facts.core_type != null) or
            field.element_byte_size != expected_size or field.element_alignment != expected_size or
            field.element_stride != expected_size)
        {
            return error.UnsupportedMarshalShape;
        }
    }

    try generated_text.append_block(allocator, out, 4,
        \\(local $__gc_length_0 i32)
        \\(local $__gc_index_0 i32)
        \\(local $__cabi_ptr_0 i32)
        \\(local $__gc_values_0 (ref $do_bytes))
        \\(local $__gc_length_1 i32)
        \\(local $__gc_index_1 i32)
        \\(local $__cabi_ptr_1 i32)
        \\(local $__gc_copy_bytes_1 i32)
        \\(local $__gc_copy_bytes64_1 i64)
        \\(local $__gc_length_2 i32)
        \\(local $__gc_index_2 i32)
        \\(local $__cabi_ptr_2 i32)
        \\(local $__gc_copy_bytes_2 i32)
        \\(local $__gc_copy_bytes64_2 i64)
        \\(local $__memory_bytes i64)
        \\(local $__gc_alloc_mask i32)
        \\(local $__gc_cleanup_trap i32)
        \\
    );

    for (fields, 0..) |field, slot| {
        try append_fmt(allocator, out, "    (local $__gc_values_{[slot]d} (ref {[array_type]s}))\n", .{
            .slot = slot + 1,
            .array_type = scalar_list_gc_type(field.element_kind),
        });
    }
    try out.appendSlice(allocator, "    block $__text_two_lists_cleanup\n");

    var text_path = std.ArrayList(RecordPathSegment).empty;
    defer text_path.deinit(allocator);
    try text_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 1 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\ref.as_non_null
        \\struct.get $do_text $length
        \\local.set $__gc_length_0
        \\
    );
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, text_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\ref.as_non_null
        \\struct.get $do_text $bytes
        \\ref.as_non_null
        \\local.set $__gc_values_0
        \\local.get $__gc_values_0
        \\array.len
        \\local.get $__gc_length_0
        \\i32.lt_u
        \\if unreachable end
        \\i32.const 0
        \\i32.const 0
        \\i32.const 1
        \\local.get $__gc_length_0
        \\
    );
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\local.set $__cabi_ptr_0
        \\i32.const 1
        \\local.set $__gc_alloc_mask
        \\
    );
    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_0", "__gc_length_0", "__text_two_lists_cleanup");
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__gc_index_0
        \\block $__text_two_lists_text_copy_done
        \\  loop $__text_two_lists_text_copy
        \\    local.get $__gc_index_0
        \\    local.get $__gc_length_0
        \\    i32.ge_u
        \\    br_if $__text_two_lists_text_copy_done
        \\    local.get $__cabi_ptr_0
        \\    local.get $__gc_index_0
        \\    i32.add
        \\    local.get $__gc_values_0
        \\    local.get $__gc_index_0
        \\    array.get_s $do_bytes
        \\    i32.store8
        \\    local.get $__gc_index_0
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__gc_index_0
        \\    br $__text_two_lists_text_copy
        \\  end
        \\end
        \\
    );

    const alloc_masks = [_]u32{ 3, 7 };
    for (fields, 0..) |field, slot| {
        const field_index = slot + 2;
        var list_path = std.ArrayList(RecordPathSegment).empty;
        defer list_path.deinit(allocator);
        try list_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = field_index });
        try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, list_path.items);
        try generated_text.append_fmt_block(allocator, out, 4,
            \\ref.as_non_null
            \\local.set $__gc_values_{[slot]d}
            \\local.get $__gc_values_{[slot]d}
            \\array.len
            \\local.set $__gc_length_{[slot]d}
            \\local.get $__gc_length_{[slot]d}
            \\i32.const {[capacity]d}
            \\i32.gt_u
            \\
        , .{ .slot = slot + 1, .capacity = field.capacity });
        try emit_trap_guard_branch_to_cleanup(allocator, out, "__text_two_lists_cleanup");
        try append_copy_byte_count_for_locals(
            allocator,
            out,
            if (slot == 0) "__gc_length_1" else "__gc_length_2",
            if (slot == 0) "__gc_copy_bytes_1" else "__gc_copy_bytes_2",
            if (slot == 0) "__gc_copy_bytes64_1" else "__gc_copy_bytes64_2",
            field.element_stride,
        );
        try generated_text.append_fmt_block(allocator, out, 4,
            \\i32.const 0
            \\i32.const 0
            \\i32.const {[alignment]d}
            \\local.get $__gc_copy_bytes_{[slot]d}
            \\
        , .{ .alignment = field.element_alignment, .slot = slot + 1 });
        try append_named_call(allocator, out, config.realloc_name);
        try generated_text.append_fmt_block(allocator, out, 4,
            \\local.set $__cabi_ptr_{[slot]d}
            \\i32.const {[alloc_mask]d}
            \\local.set $__gc_alloc_mask
            \\
        , .{ .slot = slot + 1, .alloc_mask = alloc_masks[slot] });
        try emit_span_guard_branch_to_cleanup(
            allocator,
            out,
            if (slot == 0) "__cabi_ptr_1" else "__cabi_ptr_2",
            if (slot == 0) "__gc_copy_bytes_1" else "__gc_copy_bytes_2",
            "__text_two_lists_cleanup",
        );
        try generated_text.append_fmt_block(allocator, out, 4,
            \\i32.const 0
            \\local.set $__gc_index_{[slot]d}
            \\block $__text_two_lists_copy_done_{[slot]d}
            \\  loop $__text_two_lists_copy_{[slot]d}
            \\    local.get $__gc_index_{[slot]d}
            \\    local.get $__gc_length_{[slot]d}
            \\    i32.ge_u
            \\    br_if $__text_two_lists_copy_done_{[slot]d}
            \\    local.get $__cabi_ptr_{[slot]d}
            \\    local.get $__gc_index_{[slot]d}
            \\
        , .{ .slot = slot + 1 });
        if (field.element_stride == 1) {
            try out.appendSlice(allocator, "        i32.add\n");
        } else {
            try generated_text.append_fmt_block(allocator, out, 8,
                \\i32.const {[stride]d}
                \\i32.mul
                \\i32.add
                \\
            , .{ .stride = field.element_stride });
        }
        try generated_text.append_fmt_block(allocator, out, 8,
            \\local.get $__gc_values_{[slot]d}
            \\local.get $__gc_index_{[slot]d}
            \\{[load]s}
            \\{[store]s}
            \\local.get $__gc_index_{[slot]d}
            \\i32.const 1
            \\i32.add
            \\local.set $__gc_index_{[slot]d}
            \\br $__text_two_lists_copy_{[slot]d}
            \\end
            \\end
            \\
        , .{
            .slot = slot + 1,
            .load = scalar_list_load_instruction(field.element_kind),
            .store = scalar_list_store_instruction(field.element_kind),
        });
    }

    var code_path = std.ArrayList(RecordPathSegment).empty;
    defer code_path.deinit(allocator);
    try code_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 0 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, code_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\local.get $__cabi_ptr_0
        \\local.get $__gc_length_0
        \\local.get $__cabi_ptr_1
        \\local.get $__gc_length_1
        \\local.get $__cabi_ptr_2
        \\local.get $__gc_length_2
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try out.appendSlice(allocator, "    end\n");
    try emit_conditional_cleanup(allocator, out, 4, .{
        .pointer_local = "__cabi_ptr_2",
        .length_local = "__gc_length_2",
        .size_local = "__gc_copy_bytes_2",
        .alignment = fields[1].element_alignment,
    }, config.realloc_name);
    try emit_conditional_cleanup(allocator, out, 2, .{
        .pointer_local = "__cabi_ptr_1",
        .length_local = "__gc_length_1",
        .size_local = "__gc_copy_bytes_1",
        .alignment = fields[0].element_alignment,
    }, config.realloc_name);
    try emit_conditional_cleanup(allocator, out, 1, .{
        .pointer_local = "__cabi_ptr_0",
        .length_local = "__gc_length_0",
    }, config.realloc_name);
    try generated_text.append_block(allocator, out, 0,
        \\    local.get $__gc_cleanup_trap
        \\    if unreachable end
        \\)
        \\
    );
}

fn emit_record_lower_managed_scalar_list_pair(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: *const marshal.SyncValuePlan,
    memory_plan: *const marshal_ops.MemoryPlan,
    config: EmitConfig,
) !void {
    const root = &plan.root;
    if (root.kind != .record or root.children.len != memory_plan.record_field_count or root.children.len != 3) {
        return error.UnsupportedMarshalShape;
    }
    const pair = memory_plan.managed_scalar_list_pair_lower orelse return error.UnsupportedMarshalShape;
    const fields = [_]marshal_ops.ManagedScalarListField{ pair.first, pair.second };
    for (fields, 0..) |field, slot| {
        if (field.field_index != slot + 1 or field.pointer_offset != 0 or field.length_offset != 4 or
            field.element_kind != .u32 or field.element_byte_size != 4 or field.element_alignment != 4 or
            field.element_stride != 4 or field.capacity == 0)
        {
            return error.UnsupportedMarshalShape;
        }
        const payload = &root.children[field.field_index];
        if (payload.kind != .list or payload.children.len != 1) return error.UnsupportedMarshalShape;
        const element = &payload.children[0];
        if (element.kind != .scalar or element.scalar_kind != .u32) return error.UnsupportedMarshalShape;
        const element_facts = element.measured orelse return error.MeasuredChildMissing;
        if (element_facts.byte_size != 4 or element_facts.alignment != 4 or element_facts.core_type != .i32) {
            return error.UnsupportedMarshalShape;
        }
    }
    if (root.children[0].kind != .scalar or root.children[0].scalar_kind != .u32) {
        return error.UnsupportedMarshalShape;
    }

    try generated_text.append_block(allocator, out, 4,
        \\(local $__gc_length_0 i32)
        \\(local $__gc_index_0 i32)
        \\(local $__cabi_ptr_0 i32)
        \\(local $__gc_values_0 (ref $do_u32))
        \\(local $__gc_copy_bytes_0 i32)
        \\(local $__gc_copy_bytes64_0 i64)
        \\(local $__gc_length_1 i32)
        \\(local $__gc_index_1 i32)
        \\(local $__cabi_ptr_1 i32)
        \\(local $__gc_values_1 (ref $do_u32))
        \\(local $__gc_copy_bytes_1 i32)
        \\(local $__gc_copy_bytes64_1 i64)
        \\(local $__memory_bytes i64)
        \\(local $__gc_alloc_mask i32)
        \\(local $__gc_cleanup_trap i32)
        \\block $__two_list_cleanup
        \\
    );

    var first_path = std.ArrayList(RecordPathSegment).empty;
    defer first_path.deinit(allocator);
    try first_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 1 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, first_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\ref.as_non_null
        \\local.set $__gc_values_0
        \\local.get $__gc_values_0
        \\array.len
        \\local.set $__gc_length_0
        \\
    );
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__gc_length_0
        \\i32.const {[capacity]d}
        \\i32.gt_u
        \\if unreachable end
        \\
    , .{ .capacity = fields[0].capacity });
    try append_copy_byte_count_for_locals(
        allocator,
        out,
        "__gc_length_0",
        "__gc_copy_bytes_0",
        "__gc_copy_bytes64_0",
        fields[0].element_stride,
    );
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\i32.const 0
        \\i32.const 4
        \\local.get $__gc_copy_bytes_0
        \\
    );
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\local.set $__cabi_ptr_0
        \\i32.const 1
        \\local.set $__gc_alloc_mask
        \\
    );
    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_0", "__gc_copy_bytes_0", "__two_list_cleanup");
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__gc_index_0
        \\block $__two_list_first_copy_done
        \\  loop $__two_list_first_copy
        \\    local.get $__gc_index_0
        \\    local.get $__gc_length_0
        \\    i32.ge_u
        \\    br_if $__two_list_first_copy_done
        \\    local.get $__cabi_ptr_0
        \\    local.get $__gc_index_0
        \\    i32.const 4
        \\    i32.mul
        \\    i32.add
        \\    local.get $__gc_values_0
        \\    local.get $__gc_index_0
        \\    array.get $do_u32
        \\    i32.store
        \\    local.get $__gc_index_0
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__gc_index_0
        \\    br $__two_list_first_copy
        \\  end
        \\end
        \\
    );

    var second_path = std.ArrayList(RecordPathSegment).empty;
    defer second_path.deinit(allocator);
    try second_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 2 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, second_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\ref.as_non_null
        \\local.set $__gc_values_1
        \\local.get $__gc_values_1
        \\array.len
        \\local.set $__gc_length_1
        \\
    );
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get $__gc_length_1
        \\i32.const {[capacity]d}
        \\i32.gt_u
        \\
    , .{ .capacity = fields[1].capacity });
    try emit_trap_guard_branch_to_cleanup(allocator, out, "__two_list_cleanup");
    try append_copy_byte_count_for_locals(
        allocator,
        out,
        "__gc_length_1",
        "__gc_copy_bytes_1",
        "__gc_copy_bytes64_1",
        fields[1].element_stride,
    );
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\i32.const 0
        \\i32.const 4
        \\local.get $__gc_copy_bytes_1
        \\
    );
    try append_named_call(allocator, out, config.realloc_name);
    try generated_text.append_block(allocator, out, 4,
        \\local.set $__cabi_ptr_1
        \\i32.const 3
        \\local.set $__gc_alloc_mask
        \\
    );
    try emit_span_guard_branch_to_cleanup(allocator, out, "__cabi_ptr_1", "__gc_copy_bytes_1", "__two_list_cleanup");
    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__gc_index_1
        \\block $__two_list_second_copy_done
        \\  loop $__two_list_second_copy
        \\    local.get $__gc_index_1
        \\    local.get $__gc_length_1
        \\    i32.ge_u
        \\    br_if $__two_list_second_copy_done
        \\    local.get $__cabi_ptr_1
        \\    local.get $__gc_index_1
        \\    i32.const 4
        \\    i32.mul
        \\    i32.add
        \\    local.get $__gc_values_1
        \\    local.get $__gc_index_1
        \\    array.get $do_u32
        \\    i32.store
        \\    local.get $__gc_index_1
        \\    i32.const 1
        \\    i32.add
        \\    local.set $__gc_index_1
        \\    br $__two_list_second_copy
        \\  end
        \\end
        \\
    );

    var code_path = std.ArrayList(RecordPathSegment).empty;
    defer code_path.deinit(allocator);
    try code_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 0 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, code_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\local.get $__cabi_ptr_0
        \\local.get $__gc_length_0
        \\local.get $__cabi_ptr_1
        \\local.get $__gc_length_1
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try out.appendSlice(allocator, "    end\n");
    try emit_conditional_cleanup(allocator, out, 2, .{
        .pointer_local = "__cabi_ptr_1",
        .length_local = "__gc_length_1",
        .size_local = "__gc_copy_bytes_1",
        .alignment = 4,
    }, config.realloc_name);
    try emit_conditional_cleanup(allocator, out, 1, .{
        .pointer_local = "__cabi_ptr_0",
        .length_local = "__gc_length_0",
        .size_local = "__gc_copy_bytes_0",
        .alignment = 4,
    }, config.realloc_name);
    try generated_text.append_block(allocator, out, 0,
        \\    local.get $__gc_cleanup_trap
        \\    if unreachable end
        \\)
        \\
    );
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
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    (local $__gc_length i32)
        \\    (local $__gc_index i32)
        \\    (local $__copy_bytes i32)
        \\    (local $__copy_bytes64 i64)
        \\    (local $__cabi_ptr i32)
        \\    (local $__memory_bytes i64)
        \\    (local $__gc_values (ref {[array_type]s}))
        \\
    , .{ .array_type = array_type });

    var payload_path = std.ArrayList(RecordPathSegment).empty;
    defer payload_path.deinit(allocator);
    try payload_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = field.field_index });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, payload_path.items);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    ref.as_non_null
        \\    local.set $__gc_values
        \\    local.get $__gc_values
        \\    array.len
        \\    local.set $__gc_length
        \\    local.get $__gc_length
        \\    i32.const {[capacity]d}
        \\    i32.gt_u
        \\    if unreachable end
        \\
    , .{ .capacity = field.capacity });
    try append_copy_byte_count(allocator, out, field.element_stride);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    i32.const 0
        \\    i32.const 0
        \\    i32.const {[alignment]d}
        \\    local.get $__copy_bytes
        \\
    , .{ .alignment = field.element_alignment });
    try append_named_call(allocator, out, config.realloc_name);
    try out.appendSlice(allocator, "    local.set $__cabi_ptr\n");
    try emit_span_guard(allocator, out, "__cabi_ptr", "__copy_bytes");

    try generated_text.append_block(allocator, out, 4,
        \\i32.const 0
        \\local.set $__gc_index
        \\block $__copy_done
        \\  loop $__copy
        \\    local.get $__gc_index
        \\    local.get $__gc_length
        \\    i32.ge_u
        \\    br_if $__copy_done
        \\    local.get $__cabi_ptr
        \\
    );
    if (field.element_stride == 1) {
        try generated_text.append_block(allocator, out, 8,
            \\local.get $__gc_index
            \\i32.add
            \\
        );
    } else {
        try generated_text.append_fmt_block(allocator, out, 8,
            \\        local.get $__gc_index
            \\        i32.const {[stride]d}
            \\        i32.mul
            \\        i32.add
            \\
        , .{ .stride = field.element_stride });
    }
    try generated_text.append_block(allocator, out, 8,
        \\local.get $__gc_values
        \\local.get $__gc_index
        \\
    );
    try generated_text.append_fmt_block(allocator, out, 8,
        \\        {[load]s}
        \\        {[store]s}
        \\
    , .{ .load = load_instruction, .store = store_instruction });
    try generated_text.append_block(allocator, out, 8,
        \\local.get $__gc_index
        \\i32.const 1
        \\i32.add
        \\local.set $__gc_index
        \\br $__copy
        \\  end
        \\end
        \\
    );

    var code_path = std.ArrayList(RecordPathSegment).empty;
    defer code_path.deinit(allocator);
    try code_path.append(allocator, .{ .type_name = "record", .is_root = true, .field_index = 0 });
    try emit_record_lower_input_path(allocator, out, config.input_local, config.root_type_name, code_path.items);
    try generated_text.append_block(allocator, out, 4,
        \\local.get $__cabi_ptr
        \\local.get $__gc_length
        \\
    );
    try append_named_call(allocator, out, config.canonical_call_name);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get $__cabi_ptr
        \\    local.get $__copy_bytes
        \\    i32.const {[alignment]d}
        \\    i32.const 0
        \\
    , .{ .alignment = field.element_alignment });
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
                try out.appendSlice(allocator, "    local.get $__cabi_ptr\n");
                try emit_record_lower_input_path(allocator, out, input_local, root_type_name, path.items);
                if (absolute_offset == 0) {
                    try append_fmt(allocator, out, "    {[store]s}\n", .{ .store = store_name });
                } else {
                    try append_fmt(allocator, out, "    {[store]s} offset={[offset]d}\n", .{ .store = store_name, .offset = absolute_offset });
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
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\
    , .{ .input_local = input_local });
    for (path, 0..) |segment, index| {
        if (segment.is_root) {
            try out.appendSlice(allocator, "    struct.get ");
            try append_lowercase_wat_name(allocator, out, root_type_name);
            // Standalone marshal probes declare `$do_record` with synthetic
            // `$fieldN` names. Compiler GC structs keep source field names,
            // so the ordinary route uses the stable numeric field index.
            if (std.mem.eql(u8, root_type_name, "do_record")) {
                try append_fmt(allocator, out, " $field{[field_index]d}\n", .{ .field_index = segment.field_index });
            } else {
                try append_fmt(allocator, out, " {[field_index]d}\n", .{ .field_index = segment.field_index });
            }
        } else {
            try append_fmt(allocator, out, "    struct.get $do_{[type_name]s} $field{[field_index]d}\n", .{ .type_name = segment.type_name, .field_index = segment.field_index });
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
        .text_bytes => try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get ${[input_local]s}
            \\    ref.as_non_null
            \\    struct.get $do_text $length
            \\    local.set $__gc_length
            \\
        , .{ .input_local = input_local }),
        .list_elements => try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get ${[input_local]s}
            \\    ref.as_non_null
            \\    array.len
            \\    local.set $__gc_length
            \\
        , .{ .input_local = input_local }),
        .map_entries => return error.UnsupportedMarshalShape,
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
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get $__gc_length
        \\    local.get ${[input_local]s}
        \\    ref.as_non_null
        \\    struct.get $do_text $bytes
        \\    ref.as_non_null
        \\    array.len
        \\    i32.gt_u
        \\    if unreachable end
        \\
    , .{ .input_local = input_local });
}

fn append_source_byte(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    copy_shape: marshal_ops.CopyShape,
    input_local: []const u8,
) !void {
    switch (copy_shape) {
        .scalar => return error.UnsupportedMarshalShape,
        .text_bytes => try generated_text.append_fmt_block(allocator, out, 8,
            \\        local.get ${[input_local]s}
            \\        ref.as_non_null
            \\        struct.get $do_text $bytes
            \\        ref.as_non_null
            \\        local.get $__gc_index
            \\        array.get_s $do_bytes
            \\
        , .{ .input_local = input_local }),
        .list_elements => try generated_text.append_fmt_block(allocator, out, 8,
            \\        local.get ${[input_local]s}
            \\        ref.as_non_null
            \\        local.get $__gc_index
            \\        array.get_s $do_bytes
            \\
        , .{ .input_local = input_local }),
        .map_entries => return error.UnsupportedMarshalShape,
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
        try generated_text.append_fmt_block(allocator, out, 8,
            \\        local.get ${[input_local]s}
            \\        ref.as_non_null
            \\        local.get $__gc_index
            \\        array.get $do_u32
            \\
        , .{ .input_local = input_local });
        return;
    }
    try append_source_byte(allocator, out, .list_elements, input_local);
}

fn append_copy_byte_count(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    stride: u32,
) !void {
    try append_copy_byte_count_for_locals(
        allocator,
        out,
        "__gc_length",
        "__copy_bytes",
        "__copy_bytes64",
        stride,
    );
}

fn append_copy_byte_count_for_locals(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    length_local: []const u8,
    copy_bytes_local: []const u8,
    copy_bytes64_local: []const u8,
    stride: u32,
) !void {
    if (stride == 0) return error.InvalidCopyStride;
    if (stride == 1) {
        try generated_text.append_fmt_block(allocator, out, 4,
            \\local.get ${[length_local]s}
            \\local.set ${[copy_bytes_local]s}
            \\
        , .{
            .length_local = length_local,
            .copy_bytes_local = copy_bytes_local,
        });
        return;
    }
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get ${[length_local]s}
        \\    i64.extend_i32_u
        \\    i64.const {[stride]d}
        \\    i64.mul
        \\    local.tee ${[copy_bytes64_local]s}
        \\    i64.const 4294967295
        \\    i64.gt_u
        \\    if unreachable end
        \\    local.get ${[copy_bytes64_local]s}
        \\    i32.wrap_i64
        \\    local.set ${[copy_bytes_local]s}
        \\
    , .{
        .length_local = length_local,
        .copy_bytes64_local = copy_bytes64_local,
        .copy_bytes_local = copy_bytes_local,
        .stride = stride,
    });
}

fn append_copy_byte_count_branch_to_cleanup(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    length_local: []const u8,
    copy_bytes_local: []const u8,
    copy_bytes64_local: []const u8,
    stride: u32,
    cleanup_label: []const u8,
) !void {
    if (stride == 0) return error.InvalidCopyStride;
    if (stride == 1) {
        try generated_text.append_fmt_block(allocator, out, 4,
            \\local.get ${[length_local]s}
            \\local.set ${[copy_bytes_local]s}
            \\
        , .{
            .length_local = length_local,
            .copy_bytes_local = copy_bytes_local,
        });
        return;
    }
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get ${[length_local]s}
        \\i64.extend_i32_u
        \\i64.const {[stride]d}
        \\i64.mul
        \\local.tee ${[copy_bytes64_local]s}
        \\i64.const 4294967295
        \\i64.gt_u
        \\
    , .{
        .length_local = length_local,
        .copy_bytes64_local = copy_bytes64_local,
        .stride = stride,
    });
    try emit_trap_guard_branch_to_cleanup(allocator, out, cleanup_label);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\local.get ${[copy_bytes64_local]s}
        \\i32.wrap_i64
        \\local.set ${[copy_bytes_local]s}
        \\
    , .{
        .copy_bytes64_local = copy_bytes64_local,
        .copy_bytes_local = copy_bytes_local,
    });
}

fn append_named_call(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try append_fmt(allocator, out, "    call ${[name]s}\n", .{ .name = name });
}

fn emit_span_guard(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    pointer_local: []const u8,
    length_local: []const u8,
) !void {
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    memory.size
        \\    i64.extend_i32_u
        \\    i64.const 65536
        \\    i64.mul
        \\    local.set $__memory_bytes
        \\    local.get ${[pointer_local]s}
        \\    i64.extend_i32_u
        \\    local.get $__memory_bytes
        \\    i64.gt_u
        \\    if unreachable end
        \\    local.get ${[length_local]s}
        \\    i64.extend_i32_u
        \\    local.get $__memory_bytes
        \\    local.get ${[pointer_local]s}
        \\    i64.extend_i32_u
        \\    i64.sub
        \\    i64.gt_u
        \\    if unreachable end
        \\
    , .{ .pointer_local = pointer_local, .length_local = length_local });
}

fn emit_trap_guard_branch_to_cleanup(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    cleanup_label: []const u8,
) !void {
    try generated_text.append_fmt_block(allocator, out, 4,
        \\if
        \\i32.const 1
        \\local.set $__gc_cleanup_trap
        \\br ${[cleanup_label]s}
        \\end
        \\
    , .{ .cleanup_label = cleanup_label });
}

fn emit_span_guard_branch_to_cleanup(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    pointer_local: []const u8,
    length_local: []const u8,
    cleanup_label: []const u8,
) !void {
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    memory.size
        \\    i64.extend_i32_u
        \\    i64.const 65536
        \\    i64.mul
        \\    local.set $__memory_bytes
        \\    local.get ${[pointer_local]s}
        \\    i64.extend_i32_u
        \\    local.get $__memory_bytes
        \\    i64.gt_u
        \\
    , .{ .pointer_local = pointer_local });
    try emit_trap_guard_branch_to_cleanup(allocator, out, cleanup_label);
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get ${[pointer_local]s}
        \\    i64.extend_i32_u
        \\    local.get $__memory_bytes
        \\    local.get ${[length_local]s}
        \\    i64.extend_i32_u
        \\    i64.sub
        \\    i64.gt_u
        \\
    , .{ .pointer_local = pointer_local, .length_local = length_local });
    try emit_trap_guard_branch_to_cleanup(allocator, out, cleanup_label);
}

fn emit_conditional_cleanup(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    mask_bit: u32,
    binding: CleanupBinding,
    realloc_name: []const u8,
) !void {
    const size_local = binding.size_local orelse binding.length_local;
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get $__gc_alloc_mask
        \\    i32.const {[mask_bit]d}
        \\    i32.and
        \\    if
        \\    local.get ${[pointer_local]s}
        \\    local.get ${[size_local]s}
        \\    i32.const {[alignment]d}
        \\    i32.const 0
        \\    call ${[realloc_name]s}
        \\    drop
        \\    end
        \\
    , .{
        .mask_bit = mask_bit,
        .pointer_local = binding.pointer_local,
        .size_local = size_local,
        .alignment = binding.alignment,
        .realloc_name = realloc_name,
    });
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime format: []const u8,
    args: anytype,
) !void {
    try generated_text.append_fmt(allocator, out, format, args);
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
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "[linear-temp-free] count=1") != null);
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

test "canonical marshal WAT lowers and lifts a scalar map pair-list" {
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
        .schema_hash = "sha256:6666666666666666666666666666666666666666666666666666666666666666",
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
    const lower_wat = try emit_sync_marshal_function(std.testing.allocator, &lower_plan, .{});
    defer std.testing.allocator.free(lower_wat);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "(param $input (ref null $do_map))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "array.get $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "i32.const 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "call $canonical_call") != null);
    try std.testing.expect(std.mem.lastIndexOf(u8, lower_wat, "call $cabi_realloc") != null);

    const lift_plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-map@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:7777777777777777777777777777777777777777777777777777777777777777",
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
    const lift_wat = try emit_sync_marshal_function(std.testing.allocator, &lift_plan, .{ .function_name = "map_lift" });
    defer std.testing.allocator.free(lift_wat);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "(func $map_lift") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "(result (ref null $do_map))") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, lift_wat, "array.new_default $do_u32"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, lift_wat, "array.set $do_u32"));
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "struct.new $do_map") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "call $canonical_call") != null);
}

test "canonical marshal WAT lowers and lifts a u32 text map" {
    var key = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer key.deinit();
    var value = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer value.deinit();
    var map = @import("wit_abi_types.zig").AbiType.map(std.testing.allocator, &key, &value) catch unreachable;
    defer map.deinit();

    const lower_plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-map-text@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    }, &map, .lower, .{
        .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 12,
            .element_stride = 12,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 8, .alignment = 4 },
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
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
    defer marshal.deinit_sync_value_plan(std.testing.allocator, lower_plan);
    const lower_wat = try emit_sync_marshal_function(std.testing.allocator, &lower_plan, .{});
    defer std.testing.allocator.free(lower_wat);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "(param $input (ref null $do_map))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "array.get $do_text_array") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "array.get_s $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, lower_wat, "i32.const 12") != null);

    const lift_plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-map-text@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:9999999999999999999999999999999999999999999999999999999999999999",
    }, &map, .lift, .{
        .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 12,
            .element_stride = 12,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 8, .alignment = 4 },
            .capacity = 2,
            .accepted_lengths = &.{ 0, 1, 2 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
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
    defer marshal.deinit_sync_value_plan(std.testing.allocator, lift_plan);
    const lift_wat = try emit_sync_marshal_function(std.testing.allocator, &lift_plan, .{});
    defer std.testing.allocator.free(lift_wat);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "(result (ref null $do_map))") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "array.new_default $do_text_array") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "struct.new $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, lift_wat, "array.set $do_text_array") != null);
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
    const first_free = std.mem.indexOf(u8, wat,
        \\local.get $__cabi_ptr_1
        \\    local.get $__gc_length_1
        \\    i32.const 1
        \\    i32.const 0
        \\    call $cabi_realloc
    ) orelse unreachable;
    const second_free = std.mem.indexOf(u8, wat,
        \\local.get $__cabi_ptr_0
        \\    local.get $__gc_length_0
        \\    i32.const 1
        \\    i32.const 0
        \\    call $cabi_realloc
    ) orelse unreachable;
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

test "canonical marshal WAT lowers mixed text and byte-list fields with reverse frees" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Writing",
    });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $writing))") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "i32.store8"));
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $canonical_call"));
    const call = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    const first_free = std.mem.indexOf(u8, wat,
        \\local.get $__cabi_ptr_1
        \\    local.get $__gc_length_1
        \\    i32.const 1
        \\    i32.const 0
        \\    call $cabi_realloc
    ) orelse unreachable;
    const second_free = std.mem.indexOf(u8, wat,
        \\local.get $__cabi_ptr_0
        \\    local.get $__gc_length_0
        \\    i32.const 1
        \\    i32.const 0
        \\    call $cabi_realloc
    ) orelse unreachable;
    try std.testing.expect(call < first_free);
    try std.testing.expect(first_free < second_free);

    const payload_source_guard = std.mem.indexOf(u8, wat,
        \\local.get $__gc_length_1
        \\    i32.const 4
        \\    i32.gt_u
        \\    if
        \\
    ) orelse unreachable;
    const payload_source_branch = std.mem.indexOfPos(u8, wat, payload_source_guard,
        \\i32.const 1
        \\    local.set $__gc_cleanup_trap
        \\    br $__mixed_cleanup
    ) orelse unreachable;
    try std.testing.expect(payload_source_branch < call);
    try std.testing.expect(std.mem.indexOf(u8, wat, "block $__mixed_cleanup\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $__gc_alloc_mask\n") != null);
}

test "canonical marshal WAT lowers mixed text and u32-list fields with measured stride" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
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
        .package = "demo:marshal-record-mixed-text-u32-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-text-u32-list-record-lower-v1",
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
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "i32.store\n"));
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $canonical_call"));
    const copy = std.mem.indexOf(u8, wat, "array.get $do_u32") orelse unreachable;
    const call = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    const first_realloc = std.mem.indexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    const last_realloc = std.mem.lastIndexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    try std.testing.expect(first_realloc < copy);
    try std.testing.expect(copy < call);
    try std.testing.expect(call < last_realloc);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        \\local.get $__gc_copy_bytes_1
        \\    i32.const 4
        \\    i32.const 0
        \\    call $cabi_realloc
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        \\local.get $__gc_length_1
        \\    i32.const 3
        \\    i32.gt_u
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param i32 i32 i32 i32 i32)") == null);
}

test "mixed lower cleanup honors configured realloc name" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit_conditional_cleanup(std.testing.allocator, &out, 1, .{
        .pointer_local = "payload_ptr",
        .length_local = "payload_len",
    }, "custom_realloc");
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call $custom_realloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call $cabi_realloc") == null);
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

test "canonical marshal WAT lowers bounded record with two u32-list fields" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Writing",
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $writing))") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get $do_u32"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "i32.store\n"));
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $canonical_call"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $__gc_alloc_mask") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 2") != null);

    const first_copy = std.mem.indexOf(u8, wat, "array.get $do_u32") orelse unreachable;
    const second_copy = std.mem.indexOfPos(u8, wat, first_copy + 1, "array.get $do_u32") orelse unreachable;
    const first_guard = std.mem.indexOf(u8, wat, "local.get $__cabi_ptr_0\n    i64.extend_i32_u") orelse unreachable;
    const second_guard = std.mem.indexOf(u8, wat, "local.get $__cabi_ptr_1\n    i64.extend_i32_u") orelse unreachable;
    const call = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    try std.testing.expect(first_guard < first_copy);
    try std.testing.expect(second_guard < second_copy);
    try std.testing.expect(first_copy < second_copy);
    try std.testing.expect(second_copy < call);
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_0\n    local.get $__gc_length_0\n    local.get $__cabi_ptr_1\n    local.get $__gc_length_1\n    call $canonical_call",
    ) != null);

    const first_call = std.mem.indexOf(u8, wat, "call $cabi_realloc") orelse unreachable;
    const second_call = std.mem.indexOfPos(u8, wat, first_call + 1, "call $cabi_realloc") orelse unreachable;
    const third_call = std.mem.indexOfPos(u8, wat, second_call + 1, "call $cabi_realloc") orelse unreachable;
    const fourth_call = std.mem.indexOfPos(u8, wat, third_call + 1, "call $cabi_realloc") orelse unreachable;
    try std.testing.expect(first_call < first_copy);
    try std.testing.expect(second_call < second_copy);
    try std.testing.expect(call < third_call);
    try std.testing.expect(call < fourth_call);
    const free_second = std.mem.indexOfPos(u8, wat, call + "call $canonical_call".len, "local.get $__cabi_ptr_1") orelse unreachable;
    const free_first = std.mem.indexOfPos(u8, wat, free_second + 1, "local.get $__cabi_ptr_0") orelse unreachable;
    try std.testing.expect(free_second < free_first);
    try std.testing.expect(std.mem.indexOf(u8, wat, "block $__two_list_cleanup") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "br $__mixed_cleanup") == null);
}

test "canonical marshal WAT lowers bounded record with text and two u32-list fields" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Writing",
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "block $__text_two_lists_cleanup") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get $do_u32"));
    try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, wat, "call $cabi_realloc"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $canonical_call"));
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_0\n    local.get $__gc_length_0\n    local.get $__cabi_ptr_1\n    local.get $__gc_length_1\n    local.get $__cabi_ptr_2\n    local.get $__gc_length_2\n    call $canonical_call",
    ) != null);
    const text_copy = std.mem.indexOf(u8, wat, "array.get_s $do_bytes") orelse unreachable;
    const first_copy = std.mem.indexOf(u8, wat, "array.get $do_u32") orelse unreachable;
    const second_copy = std.mem.indexOfPos(u8, wat, first_copy + 1, "array.get $do_u32") orelse unreachable;
    const call = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    try std.testing.expect(text_copy < first_copy);
    try std.testing.expect(first_copy < second_copy);
    try std.testing.expect(second_copy < call);
}

test "canonical marshal WAT lowers mixed text byte/u32 lists with guarded reverse cleanup" {
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Writing",
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.get_s $do_bytes"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "array.get $do_u32"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $canonical_call"));
    try std.testing.expect(std.mem.indexOf(u8, wat,
        "local.get $input\n    ref.as_non_null\n    struct.get $writing 0\n    local.get $__cabi_ptr_0\n    local.get $__gc_length_0\n    local.get $__cabi_ptr_1\n    local.get $__gc_length_1\n    local.get $__cabi_ptr_2\n    local.get $__gc_length_2\n    call $canonical_call",
    ) != null);

    const text_copy = std.mem.indexOf(u8, wat, "array.get_s $do_bytes") orelse unreachable;
    const bytes_copy = std.mem.indexOfPos(u8, wat, text_copy + 1, "array.get_s $do_bytes") orelse unreachable;
    const values_copy = std.mem.indexOf(u8, wat, "array.get $do_u32") orelse unreachable;
    const bytes_guard = std.mem.indexOf(u8, wat, "local.get $__cabi_ptr_1\n    i64.extend_i32_u") orelse unreachable;
    const values_guard = std.mem.indexOf(u8, wat, "local.get $__cabi_ptr_2\n    i64.extend_i32_u") orelse unreachable;
    const call = std.mem.indexOf(u8, wat, "call $canonical_call") orelse unreachable;
    try std.testing.expect(bytes_guard < bytes_copy);
    try std.testing.expect(values_guard < values_copy);
    try std.testing.expect(bytes_copy < values_copy);
    try std.testing.expect(values_copy < call);

    const values_free = std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_2\n    local.get $__gc_copy_bytes_2\n    i32.const 4\n    i32.const 0\n    call $cabi_realloc",
    ) orelse unreachable;
    const bytes_free = std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_1\n    local.get $__gc_copy_bytes_1\n    i32.const 1\n    i32.const 0\n    call $cabi_realloc",
    ) orelse unreachable;
    const label_free = std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_0\n    local.get $__gc_length_0\n    i32.const 1\n    i32.const 0\n    call $cabi_realloc",
    ) orelse unreachable;
    try std.testing.expect(call < values_free);
    try std.testing.expect(values_free < bytes_free);
    try std.testing.expect(bytes_free < label_free);
}

test "canonical marshal WAT lifts mixed text and two u32-list fields with reverse cleanup" {
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
        .package = "demo:marshal-record-mixed-text-two-u32-lists-lift@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-text-two-u32-lists-record-lift-v1",
    }, &value, .lift, .{
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

    const wat = try emit_sync_marshal_function(std.testing.allocator, &plan, .{
        .root_type_name = "Reading",
        .canonical_call_name = "__gc_canonical_call",
    });
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $reading))") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "i32.load8_u"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "array.set $do_bytes"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "array.set $do_u32"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "call $__gc_canonical_call"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "block $__text_two_lists_lift_cleanup") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $__gc_alloc_mask") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $reading") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed") == null);

    const callback = std.mem.indexOf(u8, wat, "call $__gc_canonical_call") orelse unreachable;
    const construct = std.mem.indexOf(u8, wat, "struct.new $reading") orelse unreachable;
    try std.testing.expect(callback < construct);

    const second_free = std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_2\n    local.get $__gc_copy_bytes_2\n    i32.const 4\n    i32.const 0\n    call $cabi_realloc",
    ) orelse unreachable;
    const first_free = std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_1\n    local.get $__gc_copy_bytes_1\n    i32.const 4\n    i32.const 0\n    call $cabi_realloc",
    ) orelse unreachable;
    const label_free = std.mem.indexOf(u8, wat,
        "local.get $__cabi_ptr_0\n    local.get $__gc_length_0\n    i32.const 1\n    i32.const 0\n    call $cabi_realloc",
    ) orelse unreachable;
    try std.testing.expect(construct < second_free);
    try std.testing.expect(second_free < first_free);
    try std.testing.expect(first_free < label_free);
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
