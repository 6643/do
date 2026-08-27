//! Shared GC WAT emit fragments used by migration adapters and the final backend.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
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
    try generated_text.append_fmt(allocator, out,
        "  (func ${[function_name]s} (param ${[value_name]s} (ref null $do_text)) (result (ref null $do_text))\n",
        .{ .function_name = plan.function_name, .value_name = plan.value_name });
    try generated_text.append_fmt(allocator, out, "    local.get ${[value_name]s})\n", .{ .value_name = plan.value_name });
    try generated_text.append_block(
        allocator,
        out,
        2,
        \\  (func (export "probe") (result i32)
        \\    (local $value (ref null $do_text))
        \\    i32.const 27815
        \\    ref.null $do_bytes
        \\    struct.new $do_text
        \\
        ,
    );
    try generated_text.append_fmt(allocator, out, "    call ${[function_name]s}\n", .{ .function_name = plan.function_name });
    try generated_text.append_block(
        allocator,
        out,
        0,
        \\    local.set $value
        \\    local.get $value
        \\    ref.as_non_null
        \\    struct.get $do_text $length)
        \\)
        \\
        ,
    );
}

fn emit_text_identity_fragment(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    plan: TextIdentityPlan,
) !void {
    try generated_text.append_fmt(allocator, out,
        "  (func ${[function_name]s} (param ${[value_name]s} (ref null $do_text)) (result (ref null $do_text))\n",
        .{ .function_name = plan.function_name, .value_name = plan.value_name });
    try generated_text.append_fmt(allocator, out, "    local.get ${[value_name]s})\n", .{ .value_name = plan.value_name });
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
    try generated_text.append_block(
        allocator,
        out,
        2,
        \\  (func $__gc_copy_set (param $input (ref null $do_bytes)) (result (ref $do_bytes))
        \\    (local $__gc_next (ref $do_bytes))
        \\    (local $__gc_length i32)
        \\    local.get $input
        \\    ref.as_non_null
        \\    array.len
        \\    local.set $__gc_length
        \\    local.get $__gc_length
        \\    i32.eqz
        \\    if unreachable end
        \\    local.get $__gc_length
        \\    array.new_default $do_bytes
        \\    local.set $__gc_next
        \\    local.get $__gc_next
        \\    i32.const 0
        \\    local.get $input
        \\    ref.as_non_null
        \\    i32.const 0
        \\    local.get $__gc_length
        \\    array.copy $do_bytes $do_bytes
        \\    local.get $__gc_next
        \\    i32.const 0
        \\    i32.const 65
        \\    array.set $do_bytes
        \\    local.get $__gc_next)
        \\
        ,
    );
    try generated_text.append_fmt(allocator, out,
        "  (func ${[function_name]s} (param ${[receiver_name]s} (ref null ${[struct_name]s})) (result (ref null ${[struct_name]s}))\n",
        .{ .function_name = source_function_name, .receiver_name = source_receiver_name, .struct_name = struct_name });
    if (has_scalar_field) {
        try out.appendSlice(allocator, "    (local $__gc_scalar i32)\n");
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get ${[receiver_name]s}
            \\    ref.as_non_null
            \\    struct.get ${[struct_name]s} ${[field_name]s}
            \\    local.set $__gc_scalar
            \\
        , .{ .receiver_name = source_receiver_name, .struct_name = struct_name, .field_name = source_scalar_field_name });
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get ${[receiver_name]s}
            \\    ref.as_non_null
            \\    struct.get ${[struct_name]s} ${[field_name]s}
            \\    call $__gc_copy_set
            \\    local.get $__gc_scalar
            \\    struct.new ${[struct_name]s})
            \\
        , .{ .receiver_name = source_receiver_name, .struct_name = struct_name, .field_name = source_value_field_name });
    } else {
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get ${[receiver_name]s}
            \\    ref.as_non_null
            \\    struct.get ${[struct_name]s} ${[field_name]s}
            \\    call $__gc_copy_set
            \\    struct.new ${[struct_name]s})
            \\
        , .{ .receiver_name = source_receiver_name, .struct_name = struct_name, .field_name = source_value_field_name });
    }
    try generated_text.append_fmt_block(allocator, out, 2,
        \\  (func (export "probe") (result i32)
        \\    (local $original (ref ${[struct_name]s}))
        \\    (local $updated (ref null ${[struct_name]s}))
        \\
    , .{ .struct_name = struct_name });
    try generated_text.append_block(
        allocator,
        out,
        4,
        \\    i32.const 1
        \\    i32.const 2
        \\    i32.const 3
        \\    array.new_fixed $do_bytes 3
        \\
        ,
    );
    if (has_scalar_field) try out.appendSlice(allocator, "    i32.const 9\n");
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    struct.new ${[struct_name]s}
        \\    local.tee $original
        \\    call ${[function_name]s}
        \\    local.set $updated
        \\    local.get $original
        \\    struct.get ${[struct_name]s} ${[field_name]s}
        \\
    , .{ .struct_name = struct_name, .function_name = source_function_name, .field_name = source_value_field_name });
    try generated_text.append_block(
        allocator,
        out,
        4,
        \\    ref.as_non_null
        \\    i32.const 0
        \\    array.get_s $do_bytes
        \\    i32.const 1
        \\    i32.ne
        \\    if unreachable end
        \\
        ,
    );
    if (has_scalar_field) {
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get $original
            \\    struct.get ${[struct_name]s} ${[field_name]s}
            \\    i32.const 9
            \\    i32.ne
            \\    if unreachable end
            \\
        , .{ .struct_name = struct_name, .field_name = source_scalar_field_name });
    }
    try generated_text.append_fmt_block(allocator, out, 4,
        \\    local.get $updated
        \\    ref.as_non_null
        \\    struct.get ${[struct_name]s} ${[field_name]s}
        \\
    , .{ .struct_name = struct_name, .field_name = source_value_field_name });
    try generated_text.append_block(
        allocator,
        out,
        4,
        \\    ref.as_non_null
        \\    i32.const 0
        \\    array.get_s $do_bytes
        \\    i32.const 65
        \\    i32.ne
        \\    if unreachable end
        \\
        ,
    );
    if (has_scalar_field) {
        try generated_text.append_fmt_block(allocator, out, 4,
            \\    local.get $updated
            \\    ref.as_non_null
            \\    struct.get ${[struct_name]s} ${[field_name]s}
            \\    i32.const 9
            \\    i32.ne
            \\    if unreachable end
            \\
        , .{ .struct_name = struct_name, .field_name = source_scalar_field_name });
    }
    try generated_text.append_block(allocator, out, 2,
        \\    i32.const 27815)
        \\  )
        \\
    );
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
    try generated_text.append_block(
        allocator,
        out,
        0,
        \\  (func $update (param $input (ref null $tuple_text_bytes)) (result (ref null $tuple_text_bytes))
        \\    (local $__gc_next (ref $do_bytes))
        \\    (local $__gc_length i32)
        \\    (local $text (ref null $do_text))
        \\    local.get $input
        \\    ref.as_non_null
        \\    struct.get $tuple_text_bytes $text
        \\    local.set $text
        \\    local.get $input
        \\    ref.as_non_null
        \\    struct.get $tuple_text_bytes $bytes
        \\    ref.as_non_null
        \\    array.len
        \\    local.set $__gc_length
        \\    local.get $__gc_length
        \\    i32.eqz
        \\    if unreachable end
        \\    local.get $__gc_length
        \\    array.new_default $do_bytes
        \\    local.set $__gc_next
        \\    local.get $__gc_next
        \\    i32.const 0
        \\    local.get $input
        \\    ref.as_non_null
        \\    struct.get $tuple_text_bytes $bytes
        \\    ref.as_non_null
        \\    i32.const 0
        \\    local.get $__gc_length
        \\    array.copy $do_bytes $do_bytes
        \\    local.get $__gc_next
        \\    i32.const 0
        \\    i32.const 65
        \\    array.set $do_bytes
        \\    local.get $text
        \\    local.get $__gc_next
        \\    struct.new $tuple_text_bytes)
        \\  (func (export "probe") (result i32)
        \\    (local $original (ref $tuple_text_bytes))
        \\    (local $updated (ref null $tuple_text_bytes))
        \\    i32.const 27815
        \\    ref.null $do_bytes
        \\    struct.new $do_text
        \\    i32.const 1
        \\    i32.const 2
        \\    i32.const 3
        \\    array.new_fixed $do_bytes 3
        \\    struct.new $tuple_text_bytes
        \\    local.tee $original
        \\    call $update
        \\    local.set $updated
        \\    local.get $original
        \\    struct.get $tuple_text_bytes $text
        \\    ref.as_non_null
        \\    struct.get $do_text $length
        \\    i32.const 27815
        \\    i32.ne
        \\    if unreachable end
        \\    local.get $original
        \\    struct.get $tuple_text_bytes $bytes
        \\    ref.as_non_null
        \\    i32.const 0
        \\    array.get_s $do_bytes
        \\    i32.const 1
        \\    i32.ne
        \\    if unreachable end
        \\    local.get $updated
        \\    ref.as_non_null
        \\    struct.get $tuple_text_bytes $text
        \\    ref.as_non_null
        \\    struct.get $do_text $length
        \\    i32.const 27815
        \\    i32.ne
        \\    if unreachable end
        \\    local.get $updated
        \\    ref.as_non_null
        \\    struct.get $tuple_text_bytes $bytes
        \\    ref.as_non_null
        \\    i32.const 0
        \\    array.get_s $do_bytes
        \\    i32.const 65
        \\    i32.ne
        \\    if unreachable end
        \\    i32.const 27815)
        \\)
        \\
        ,
    );
}

fn lower_wat_name(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const name = try allocator.alloc(u8, source.len);
    for (source, 0..) |ch, index| name[index] = std.ascii.toLower(ch);
    return name;
}
