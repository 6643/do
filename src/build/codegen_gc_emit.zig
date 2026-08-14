//! Shared GC WAT emit fragments used by migration adapters and the final backend.
const std = @import("std");
const runtime_gc_prelude = @import("runtime_gc_prelude_wat.zig");
const runtime_gc_wat = @import("runtime_gc_wat.zig");
const gc_layout = @import("codegen_gc_layout.zig");

pub const TextIdentityPlan = struct {
    function_name: []const u8,
    value_name: []const u8,
};

pub const ManagedStructSetPlan = struct {
    managed_field: ManagedStructFieldBinding = .{},
    scalar_field: ?ManagedStructFieldBinding = null,
    function_binding: ManagedStructFunctionBinding = .{},
};

pub const ManagedStructFieldBinding = struct {
    source_type_name: []const u8 = "box",
    source_field_name: []const u8 = "value",
};

pub const ManagedStructFunctionBinding = struct {
    source_name: []const u8 = "update",
    receiver_name: []const u8 = "input",
};

pub const ManagedTupleSetPlan = struct {
    layout: ?gc_layout.GcTupleLayout = null,
};

pub const GcModuleEmitter = struct {
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    bytes_prelude_emitted: bool = false,
    text_prelude_emitted: bool = false,
    begun: bool = false,
    ended: bool = false,

    pub fn init(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) GcModuleEmitter {
        return .{ .allocator = allocator, .out = out };
    }

    pub fn begin(self: *GcModuleEmitter) !void {
        if (self.begun) return error.GcModuleAlreadyBegun;
        self.begun = true;
        try self.out.appendSlice(self.allocator, "(module\n");
    }

    pub fn end(self: *GcModuleEmitter) !void {
        if (!self.begun or self.ended) return error.GcModuleNotOpen;
        self.ended = true;
        try self.out.appendSlice(self.allocator, ")\n");
    }

    pub fn emit_text_identity(self: *GcModuleEmitter, plan: TextIdentityPlan) !void {
        try self.ensure_open();
        try self.emit_text_prelude();
        try emit_text_identity_fragment(self.allocator, self.out, plan);
    }

    fn ensure_open(self: *GcModuleEmitter) !void {
        if (!self.begun or self.ended) return error.GcModuleNotOpen;
    }

    fn emit_bytes_prelude(self: *GcModuleEmitter) !void {
        if (self.bytes_prelude_emitted) return;
        self.bytes_prelude_emitted = true;
        try runtime_gc_prelude.emit_bytes_prelude(self.allocator, self.out);
    }

    fn emit_text_prelude(self: *GcModuleEmitter) !void {
        try self.emit_bytes_prelude();
        if (self.text_prelude_emitted) return;
        self.text_prelude_emitted = true;
        try runtime_gc_wat.emit_text_type(self.allocator, self.out);
    }
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

fn emit_text_identity_fragment(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: TextIdentityPlan,
) !void {
    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null $do_text)) (result (ref null $do_text))\n", .{ plan.function_name, plan.value_name });
    try append_fmt(allocator, out, "    local.get ${s})\n", .{plan.value_name});
}

pub fn emit_managed_struct_set(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: ManagedStructSetPlan,
) !void {
    const source_struct_name = plan.managed_field.source_type_name;
    const source_function_name = plan.function_binding.source_name;
    const source_receiver_name = plan.function_binding.receiver_name;
    const source_value_field_name = plan.managed_field.source_field_name;
    const source_scalar_field_name = if (plan.scalar_field) |field| field.source_field_name else "";
    const has_scalar_field = plan.scalar_field != null;
    const struct_name = try lower_wat_name(allocator, source_struct_name);
    defer allocator.free(struct_name);
    try out.appendSlice(allocator, "(module\n");
    try runtime_gc_prelude.emit_named_managed_struct_prelude(allocator, out, struct_name, source_value_field_name, if (has_scalar_field) source_scalar_field_name else null);
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
            "    i32.eqz\n" ++
            "    if unreachable end\n" ++
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
    try append_fmt(allocator, out, "  (func ${s} (param ${s} (ref null ${s})) (result (ref null ${s}))\n", .{ source_function_name, source_receiver_name, struct_name, struct_name });
    if (has_scalar_field) {
        try out.appendSlice(allocator, "    (local $__gc_scalar i32)\n");
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    local.set $__gc_scalar\n", .{ source_receiver_name, struct_name, source_scalar_field_name });
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    call $__gc_copy_set\n    local.get $__gc_scalar\n    struct.new ${s})\n", .{ source_receiver_name, struct_name, source_value_field_name, struct_name });
    } else {
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    call $__gc_copy_set\n    struct.new ${s})\n", .{ source_receiver_name, struct_name, source_value_field_name, struct_name });
    }
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n    (local $original (ref ${s}))\n    (local $updated (ref null ${s}))\n", .{ struct_name, struct_name });
    try out.appendSlice(
        allocator,
        "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n",
    );
    if (has_scalar_field) try out.appendSlice(allocator, "    i32.const 9\n");
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.tee $original\n    call ${s}\n    local.set $updated\n    local.get $original\n    struct.get ${s} ${s}\n", .{ struct_name, source_function_name, struct_name, source_value_field_name });
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n",
    );
    if (has_scalar_field) {
        try append_fmt(allocator, out, "    local.get $original\n    struct.get ${s} ${s}\n    i32.const 9\n    i32.ne\n    if unreachable end\n", .{ struct_name, source_scalar_field_name });
    }
    try append_fmt(allocator, out, "    local.get $updated\n    ref.as_non_null\n    struct.get ${s} ${s}\n", .{ struct_name, source_value_field_name });
    try out.appendSlice(
        allocator,
        "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 65\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n",
    );
    if (has_scalar_field) {
        try append_fmt(allocator, out, "    local.get $updated\n    ref.as_non_null\n    struct.get ${s} ${s}\n    i32.const 9\n    i32.ne\n    if unreachable end\n", .{ struct_name, source_scalar_field_name });
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
            "    i32.eqz\n" ++
            "    if unreachable end\n" ++
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
