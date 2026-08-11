//! Shared GC WAT emit fragments used by migration adapters and the final backend.
const std = @import("std");
const runtime_gc_prelude = @import("runtime_gc_prelude_wat.zig");
const gc_layout = @import("codegen_gc_layout.zig");

pub const TextIdentityPlan = struct {
    function_name: []const u8,
    value_name: []const u8,
};

pub const ByteListSetPlan = struct {
    function_name: []const u8,
    input_name: []const u8,
    index_expr: []const u8,
    value_expr: []const u8,
};

pub const ParameterizedByteListSetPlan = struct {
    function_name: []const u8,
    input_name: []const u8,
    index_name: []const u8,
    value_name: []const u8,
};

pub const ManagedStructSetPlan = struct {
    has_scalar_field: bool = false,
    struct_name: []const u8 = "box",
    function_name: []const u8 = "update",
    receiver_name: []const u8 = "input",
    value_field_name: []const u8 = "value",
    scalar_field_name: []const u8 = "tag",
};

pub const ManagedTupleSetPlan = struct {
    layout: ?gc_layout.GcTupleLayout = null,
};

pub fn emit_text_identity(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: TextIdentityPlan,
) !void {
    try out.appendSlice(allocator, "(module\n");
    try runtime_gc_prelude.emit_text_prelude(allocator, out);
    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null $do_text)) (result (ref null $do_text))\n", .{ plan.function_name, plan.value_name });
    try append_fmt(allocator, out, "    local.get ${s})\n", .{plan.value_name});
    try out.appendSlice(
        allocator,
        "  (func (export \"probe\") (result i32)\n" ++
            "    (local $value (ref null $do_text))\n" ++
            "    i32.const 27815\n" ++
            "    ref.null $do_bytes\n" ++
            "    struct.new $do_text\n",
    );
    try append_fmt(allocator, out, "    call ${s}\n", .{plan.function_name});
    try out.appendSlice(
        allocator,
        "    local.set $value\n" ++
            "    local.get $value\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_text $length)\n" ++
            ")\n",
    );
}

pub fn emit_byte_list_set(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: ByteListSetPlan,
) !void {
    try out.appendSlice(allocator, "(module\n");
    try runtime_gc_prelude.emit_bytes_prelude(allocator, out);
    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null $do_bytes)) (result (ref null $do_bytes))\n", .{ plan.function_name, plan.input_name });
    try out.appendSlice(
        allocator,
        "    (local $__gc_next (ref $do_bytes))\n" ++
            "    (local $__gc_length i32)\n",
    );
    try append_fmt(allocator, out, "    local.get ${s}\n", .{plan.input_name});
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    local.set $__gc_length\n" ++
            "    local.get $__gc_length\n" ++
            "    array.new_default $do_bytes\n" ++
            "    local.set $__gc_next\n" ++
            "    local.get $__gc_next\n" ++
            "    i32.const 0\n",
    );
    try append_fmt(allocator, out, "    local.get ${s}\n", .{plan.input_name});
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    local.get $__gc_length\n" ++
            "    array.copy $do_bytes $do_bytes\n" ++
            "    local.get $__gc_next\n",
    );
    try append_fmt(allocator, out, "    i32.const {s}\n", .{plan.index_expr});
    try append_fmt(allocator, out, "    i32.const {s}\n", .{plan.value_expr});
    try out.appendSlice(
        allocator,
        "    array.set $do_bytes\n" ++
            "    local.get $__gc_next)\n" ++
            "  (func (export \"probe\") (result i32)\n" ++
            "    (local $input (ref $do_bytes))\n" ++
            "    (local $updated (ref null $do_bytes))\n" ++
            "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n" ++
            "    local.tee $input\n",
    );
    try append_fmt(allocator, out, "    call ${s}\n", .{plan.function_name});
    try out.appendSlice(
        allocator,
        "    local.set $updated\n" ++
            "    local.get $input\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 65\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    i32.const 27815)\n" ++
            ")\n",
    );
}

pub fn emit_parameterized_byte_list_set(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: ParameterizedByteListSetPlan,
) !void {
    try out.appendSlice(allocator, "(module\n");
    try runtime_gc_prelude.emit_bytes_prelude(allocator, out);
    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null $do_bytes)) (param ${s} i32) (param ${s} i32) (result (ref null $do_bytes))\n", .{ plan.function_name, plan.input_name, plan.index_name, plan.value_name });
    try out.appendSlice(
        allocator,
        "    (local $__gc_next (ref $do_bytes))\n" ++
            "    (local $__gc_length i32)\n",
    );
    try append_fmt(allocator, out, "    local.get ${s}\n", .{plan.input_name});
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    local.set $__gc_length\n" ++
            "    local.get $__gc_length\n" ++
            "    array.new_default $do_bytes\n" ++
            "    local.set $__gc_next\n" ++
            "    local.get $__gc_next\n" ++
            "    i32.const 0\n",
    );
    try append_fmt(allocator, out, "    local.get ${s}\n", .{plan.input_name});
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    local.get $__gc_length\n" ++
            "    array.copy $do_bytes $do_bytes\n" ++
            "    local.get $__gc_next\n",
    );
    try append_fmt(allocator, out, "    local.get ${s}\n", .{plan.index_name});
    try append_fmt(allocator, out, "    local.get ${s}\n", .{plan.value_name});
    try out.appendSlice(
        allocator,
        "    array.set $do_bytes\n" ++
            "    local.get $__gc_next)\n" ++
            "  (func (export \"probe\") (result i32)\n" ++
            "    (local $input (ref $do_bytes))\n" ++
            "    (local $updated (ref null $do_bytes))\n" ++
            "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n" ++
            "    local.tee $input\n" ++
            "    i32.const 0\n" ++
            "    i32.const 65\n",
    );
    try append_fmt(allocator, out, "    call ${s}\n", .{plan.function_name});
    try out.appendSlice(
        allocator,
        "    local.set $updated\n" ++
            "    local.get $input\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 65\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    i32.const 27815)\n" ++
            ")\n",
    );
}

pub fn emit_managed_struct_set(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: ManagedStructSetPlan,
) !void {
    const struct_name = try lower_wat_name(allocator, plan.struct_name);
    defer allocator.free(struct_name);
    try out.appendSlice(allocator, "(module\n");
    try runtime_gc_prelude.emit_named_managed_struct_prelude(allocator, out, struct_name, plan.value_field_name, if (plan.has_scalar_field) plan.scalar_field_name else null);
    try out.appendSlice(
        allocator,
        "  (func $__gc_copy_set (param $input (ref null $do_bytes)) (result (ref $do_bytes))\n" ++
            "    (local $__gc_next (ref $do_bytes))\n" ++
            "    (local $__gc_length i32)\n" ++
            "    local.get $input\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    local.set $__gc_length\n" ++
            "    local.get $__gc_length\n" ++
            "    array.new_default $do_bytes\n" ++
            "    local.set $__gc_next\n" ++
            "    local.get $__gc_next\n" ++
            "    i32.const 0\n" ++
            "    local.get $input\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    local.get $__gc_length\n" ++
            "    array.copy $do_bytes $do_bytes\n" ++
            "    local.get $__gc_next\n" ++
            "    i32.const 0\n" ++
            "    i32.const 65\n" ++
            "    array.set $do_bytes\n" ++
            "    local.get $__gc_next)\n",
    );
    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null ${s})) (result (ref null ${s}))\n", .{ plan.function_name, plan.receiver_name, struct_name, struct_name });
    if (plan.has_scalar_field) {
        try out.appendSlice(allocator, "    (local $__gc_scalar i32)\n");
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    local.set $__gc_scalar\n", .{ plan.receiver_name, struct_name, plan.scalar_field_name });
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    call $__gc_copy_set\n    local.get $__gc_scalar\n    struct.new ${s})\n", .{ plan.receiver_name, struct_name, plan.value_field_name, struct_name });
    } else {
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    call $__gc_copy_set\n    struct.new ${s})\n", .{ plan.receiver_name, struct_name, plan.value_field_name, struct_name });
    }
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n    (local $original (ref ${s}))\n    (local $updated (ref null ${s}))\n", .{ struct_name, struct_name });
    try out.appendSlice(
        allocator,
        "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n",
    );
    if (plan.has_scalar_field) try out.appendSlice(allocator, "    i32.const 9\n");
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.tee $original\n    call ${s}\n    local.set $updated\n    local.get $original\n    struct.get ${s} ${s}\n", .{ struct_name, plan.function_name, struct_name, plan.value_field_name });
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n",
    );
    if (plan.has_scalar_field) {
        try append_fmt(allocator, out, "    local.get $original\n    struct.get ${s} ${s}\n    i32.const 9\n    i32.ne\n    if unreachable end\n", .{ struct_name, plan.scalar_field_name });
    }
    try append_fmt(allocator, out, "    local.get $updated\n    ref.as_non_null\n    struct.get ${s} ${s}\n", .{ struct_name, plan.value_field_name });
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 65\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n",
    );
    if (plan.has_scalar_field) {
        try append_fmt(allocator, out, "    local.get $updated\n    ref.as_non_null\n    struct.get ${s} ${s}\n    i32.const 9\n    i32.ne\n    if unreachable end\n", .{ struct_name, plan.scalar_field_name });
    }
    try out.appendSlice(allocator, "    i32.const 27815)\n  )\n");
}

pub fn emit_managed_tuple_set(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: ManagedTupleSetPlan,
) !void {
    if (plan.layout) |layout| {
        if (layout.fields.len != 2) return error.UnsupportedGcAggregate;
        if (layout.fields[0].rep != .gc_managed or layout.fields[1].rep != .gc_managed) return error.UnsupportedGcAggregate;
        if (layout.fields[0].field_index != 0 or layout.fields[1].field_index != 1) return error.UnsupportedGcAggregate;
    }
    try out.appendSlice(allocator, "(module\n");
    try runtime_gc_prelude.emit_managed_tuple_prelude(allocator, out);
    try out.appendSlice(
        allocator,
        "  (func $update (param $input (ref null $tuple_text_bytes)) (result (ref null $tuple_text_bytes))\n" ++
            "    (local $__gc_next (ref $do_bytes))\n" ++
            "    (local $__gc_length i32)\n" ++
            "    (local $text (ref null $do_text))\n" ++
            "    local.get $input\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $tuple_text_bytes $text\n" ++
            "    local.set $text\n" ++
            "    local.get $input\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $tuple_text_bytes $bytes\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    local.set $__gc_length\n" ++
            "    local.get $__gc_length\n" ++
            "    array.new_default $do_bytes\n" ++
            "    local.set $__gc_next\n" ++
            "    local.get $__gc_next\n" ++
            "    i32.const 0\n" ++
            "    local.get $input\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $tuple_text_bytes $bytes\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    local.get $__gc_length\n" ++
            "    array.copy $do_bytes $do_bytes\n" ++
            "    local.get $__gc_next\n" ++
            "    i32.const 0\n" ++
            "    i32.const 65\n" ++
            "    array.set $do_bytes\n" ++
            "    local.get $text\n" ++
            "    local.get $__gc_next\n" ++
            "    struct.new $tuple_text_bytes)\n" ++
            "  (func (export \"probe\") (result i32)\n" ++
            "    (local $original (ref $tuple_text_bytes))\n" ++
            "    (local $updated (ref null $tuple_text_bytes))\n" ++
            "    i32.const 27815\n" ++
            "    ref.null $do_bytes\n" ++
            "    struct.new $do_text\n" ++
            "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n" ++
            "    struct.new $tuple_text_bytes\n" ++
            "    local.tee $original\n" ++
            "    call $update\n" ++
            "    local.set $updated\n" ++
            "    local.get $original\n" ++
            "    struct.get $tuple_text_bytes $text\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_text $length\n" ++
            "    i32.const 27815\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $original\n" ++
            "    struct.get $tuple_text_bytes $bytes\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $tuple_text_bytes $text\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_text $length\n" ++
            "    i32.const 27815\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $tuple_text_bytes $bytes\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 65\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    i32.const 27815)\n" ++
            ")\n",
    );
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

fn lower_wat_name(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const name = try allocator.alloc(u8, source.len);
    for (source, 0..) |ch, index| name[index] = std.ascii.toLower(ch);
    return name;
}
