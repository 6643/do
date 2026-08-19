//! Test-only parser-backed scalar-record marshal module generator.

const std = @import("std");
const marshal_route = @import("codegen_component_marshal_route.zig");
const marshal_plan = @import("codegen_component_marshal_plan.zig");
const wit_layout = @import("wit_abi_layout.zig");

const record_wit =
    \\package demo:marshal-record-assembly@1.0.0;
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

const lower_record_wit =
    \\package demo:marshal-record-lower@1.0.0;
    \\
    \\interface api {
    \\  record writing {
    \\    code: u32,
    \\    count: u32,
    \\  }
    \\
    \\  write: func(value: writing);
    \\}
    \\
    \\world probe {
    \\  import api;
    \\  export run: func() -> u32;
    \\}
;

const mixed_lower_record_wit =
    \\package demo:marshal-record-mixed-lower@1.0.0;
    \\
    \\interface api {
    \\  record writing {
    \\    code: u32,
    \\    count: u64,
    \\    status: s64,
    \\  }
    \\
    \\  write: func(value: writing);
    \\}
    \\
    \\world probe {
    \\  import api;
    \\  export run: func() -> u32;
    \\}
;

const indirect_lower_record_wit =
    \\package demo:marshal-record-indirect-lower@1.0.0;
    \\
    \\interface api {
    \\  record writing {
    \\    f0: u64,
    \\    f1: u64,
    \\    f2: u64,
    \\    f3: u64,
    \\    f4: u64,
    \\    f5: u64,
    \\    f6: u64,
    \\    f7: u64,
    \\    f8: u64,
    \\    f9: u64,
    \\    f10: u64,
    \\    f11: u64,
    \\    f12: u64,
    \\    f13: u64,
    \\    f14: u64,
    \\    f15: u64,
    \\    f16: u64,
    \\  }
    \\
    \\  write: func(value: writing);
    \\}
    \\
    \\world probe {
    \\  import api;
    \\  export run: func() -> u32;
    \\}
;

test "record probe generator emits parser-backed lift module" {
    const wat = try emit_record_marshal_module(std.testing.allocator, record_wit);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_record (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lift (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-assembly/api@1.0.0\" \"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "cabi_realloc") == null);
}

test "record probe generator emits a host executable wrapper" {
    const wat = try emit_record_host_module(std.testing.allocator, record_wit);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $run (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $marshal") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
}

test "record probe generator emits parser-backed lower module" {
    const wat = try emit_record_lower_marshal_module(std.testing.allocator, lower_record_wit);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-lower/api@1.0.0\" \"write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $input (ref null $do_record))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_record $field1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $cabi_realloc") == null);
}

test "record probe generator emits a lower host executable wrapper" {
    const wat = try emit_record_lower_host_module(std.testing.allocator, lower_record_wit);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $run (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $marshal") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "record probe generator emits a mixed scalar lower module" {
    const wat = try emit_mixed_record_lower_host_module(std.testing.allocator, mixed_lower_record_wit);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32 i64 i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-mixed-lower/api@1.0.0\" \"write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $field0 i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $field1 i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $field2 i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 35") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const -5") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param (ref") == null);
}

test "record probe generator emits an indirect scalar lower module" {
    const wat = try emit_indirect_record_lower_host_module(std.testing.allocator, indirect_lower_record_wit);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $canonical_lower (func (param i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"demo:marshal-record-indirect-lower/api@1.0.0\" \"write\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(memory (export \"memory\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $cabi_realloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store offset=128") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $__cabi_ptr") != null);
}

test "record probe rejects an invalid argument count" {
    const args = [_][]const u8{"gc-marshal-record-probe"};
    try std.testing.expectError(error.InvalidGcMarshalRecordProbeArgs, validate_probe_args(&args));
}

test "record probe accepts the host wrapper selector" {
    const args = [_][]const u8{ "gc-marshal-record-probe", "input.wit", "output.wat", "--host" };
    try validate_probe_args(&args);
}

test "record probe accepts the lower wrapper selector" {
    const args = [_][]const u8{ "gc-marshal-record-probe", "input.wit", "output.wat", "--lower-host" };
    try validate_probe_args(&args);
}

test "record probe accepts the mixed lower wrapper selector" {
    const args = [_][]const u8{ "gc-marshal-record-probe", "input.wit", "output.wat", "--lower-mixed-host" };
    try validate_probe_args(&args);
}

test "record probe accepts the indirect lower wrapper selector" {
    const args = [_][]const u8{ "gc-marshal-record-probe", "input.wit", "output.wat", "--lower-indirect-host" };
    try validate_probe_args(&args);
}

pub fn emit_record_marshal_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    return emit_record_marshal_module_for(allocator, source, "read", .lift, record_measurement());
}

pub fn emit_record_lower_marshal_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    return emit_record_marshal_module_for(allocator, source, "write", .lower, record_measurement());
}

fn emit_mixed_record_lower_marshal_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    return emit_record_marshal_module_for(allocator, source, "write", .lower, mixed_record_measurement());
}

fn emit_indirect_record_lower_marshal_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    return emit_record_marshal_module_for(allocator, source, "write", .lower, indirect_record_measurement());
}

fn emit_record_marshal_module_for(
    allocator: std.mem.Allocator,
    source: []const u8,
    member_name: []const u8,
    direction: @import("codegen_component_marshal_plan.zig").Direction,
    measured: @import("codegen_component_marshal_plan.zig").MeasuredNode,
) ![]u8 {
    return marshal_route.emit_sync_marshal_module_from_wit_source(allocator, .{
        .source = source,
        .world_name = "probe",
        .interface_name = "api",
        .member_name = member_name,
        .direction = direction,
        .measured = measured,
    });
}

fn record_measurement() @import("codegen_component_marshal_plan.zig").MeasuredNode {
    return .{
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
    };
}

fn mixed_record_measurement() @import("codegen_component_marshal_plan.zig").MeasuredNode {
    return .{
        .layout = .{ .record = .{
            .byte_size = 24,
            .alignment = 8,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
                .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        },
    };
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

fn make_indirect_record_children() [17]marshal_plan.MeasuredNode {
    var children: [17]marshal_plan.MeasuredNode = undefined;
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

fn indirect_record_measurement() marshal_plan.MeasuredNode {
    return .{
        .layout = .{ .record = .{
            .byte_size = 136,
            .alignment = 8,
            .fields = &indirect_record_fields,
            .indirect = .{
                .core_words = &.{.i32},
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            },
        } },
        .children = &indirect_record_children,
    };
}

pub fn emit_record_host_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const base = try emit_record_marshal_module(allocator, source);
    defer allocator.free(base);
    return append_record_host_entry(allocator, base);
}

pub fn emit_record_lower_host_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const base = try emit_record_lower_marshal_module(allocator, source);
    defer allocator.free(base);
    return append_record_lower_host_entry(allocator, base);
}

pub fn emit_mixed_record_lower_host_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const base = try emit_mixed_record_lower_marshal_module(allocator, source);
    defer allocator.free(base);
    return append_mixed_record_lower_host_entry(allocator, base);
}

pub fn emit_indirect_record_lower_host_module(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const base = try emit_indirect_record_lower_marshal_module(allocator, source);
    defer allocator.free(base);
    return append_indirect_record_lower_host_entry(allocator, base);
}

fn append_indirect_record_lower_host_entry(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
    try out.appendSlice(allocator,
        "  (func $run (result i32)\n" ++
            "    (local $writing (ref null $do_record))\n" ++
            "    ");
    inline for (0..17) |index| {
        try append_fmt(allocator, &out, "i64.const {d}\n    ", .{index + 1});
    }
    try out.appendSlice(allocator,
        "struct.new $do_record\n" ++
            "    local.set $writing\n" ++
            "    local.get $writing\n" ++
            "    call $marshal\n" ++
            "    i32.const 42)\n" ++
            "  (export \"run\" (func $run))\n");
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

fn append_mixed_record_lower_host_entry(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
    try out.appendSlice(allocator,
        \\  (func $run (result i32)
        \\    (local $writing (ref null $do_record))
        \\    i32.const 7
        \\    i64.const 35
        \\    i64.const -5
        \\    struct.new $do_record
        \\    local.set $writing
        \\    local.get $writing
        \\    call $marshal
        \\    i32.const 42)
        \\  (export "run" (func $run))
    );
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

fn append_record_host_entry(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
    try out.appendSlice(allocator,
        \\  (func $run (result i32)
        \\    (local $reading (ref null $do_record))
        \\    call $marshal
        \\    local.set $reading
        \\    local.get $reading
        \\    ref.as_non_null
        \\    struct.get $do_record $field0
        \\    local.get $reading
        \\    ref.as_non_null
        \\    struct.get $do_record $field1
        \\    i32.add)
        \\  (export "run" (func $run))
    );
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

fn append_record_lower_host_entry(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    const closing = ")\n";
    if (!std.mem.endsWith(u8, base, closing)) return error.InvalidGeneratedModule;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, base[0 .. base.len - closing.len]);
    try out.appendSlice(allocator,
        \\  (func $run (result i32)
        \\    (local $writing (ref null $do_record))
        \\    i32.const 7
        \\    i32.const 35
        \\    struct.new $do_record
        \\    local.set $writing
        \\    local.get $writing
        \\    call $marshal
        \\    i32.const 42)
        \\  (export "run" (func $run))
    );
    try out.appendSlice(allocator, closing);
    return out.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try validate_probe_args(args);

    const source = try std.Io.Dir.cwd().readFileAlloc(io, args[1], allocator, .limited(1024 * 1024));
    defer allocator.free(source);
    const wat = if (args.len == 3)
        try emit_record_marshal_module(allocator, source)
    else if (std.mem.eql(u8, args[3], "--host"))
        try emit_record_host_module(allocator, source)
    else if (std.mem.eql(u8, args[3], "--lower"))
        try emit_record_lower_marshal_module(allocator, source)
    else if (std.mem.eql(u8, args[3], "--lower-mixed-host"))
        try emit_mixed_record_lower_host_module(allocator, source)
    else if (std.mem.eql(u8, args[3], "--lower-indirect-host"))
        try emit_indirect_record_lower_host_module(allocator, source)
    else
        try emit_record_lower_host_module(allocator, source);
    defer allocator.free(wat);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = wat });
}

fn validate_probe_args(args: []const []const u8) !void {
    if (args.len != 3 and args.len != 4) return error.InvalidGcMarshalRecordProbeArgs;
    if (args.len == 4 and
        !std.mem.eql(u8, args[3], "--host") and
        !std.mem.eql(u8, args[3], "--lower") and
        !std.mem.eql(u8, args[3], "--lower-host") and
        !std.mem.eql(u8, args[3], "--lower-mixed-host") and
        !std.mem.eql(u8, args[3], "--lower-indirect-host")) return error.InvalidGcMarshalRecordArgs;
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
