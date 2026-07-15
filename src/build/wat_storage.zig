const std = @import("std");
const type_util = @import("type_name.zig");

/// Pure WAT helpers for managed storage (`[T]` / text-backed) object layout access.
/// Layout contract (must match `doc/memory.md` / `doc/memory_layout_structs.md`):
/// - Object handle is an i32 local; payload via `$__arc_payload`.
/// - Storage payload header is 8 bytes: `len: u32` @0, `cap: u32` @4, then element data.
/// - Builtin type ids: `[u8]`-style scalar storage `1`; generic managed storage `65535`.
/// No LocalSet / CodegenContext / token dependencies.
pub const STORAGE_PAYLOAD_HEADER_BYTES: usize = 8;
pub const TYPE_ID_STORAGE_U8: usize = 1;
pub const TYPE_ID_STORAGE_MANAGED: usize = 65535;
pub const TYPE_ID_FIRST_STRUCT: usize = TYPE_ID_STORAGE_U8 + 1;

pub const STORAGE_OVERWRITE_TMP_LOCAL = "__storage_overwrite_tmp";

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

pub fn emit_storage_payload_ptr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "    call $__arc_payload\n");
}

pub fn emit_storage_payload_ptr_with_indent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    indent: []const u8,
) !void {
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, name });
    try append_fmt(allocator, out, "{s}call $__arc_payload\n", .{indent});
}

pub fn emit_storage_len_ptr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try emit_storage_payload_ptr(allocator, out, name);
}

pub fn emit_storage_len_ptr_with_indent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    indent: []const u8,
) !void {
    try emit_storage_payload_ptr_with_indent(allocator, out, name, indent);
}

pub fn emit_storage_cap_ptr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try emit_storage_payload_ptr(allocator, out, name);
    try out.appendSlice(allocator, "    i32.const 4\n");
    try out.appendSlice(allocator, "    i32.add\n");
}

pub fn emit_storage_cap_ptr_with_indent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    indent: []const u8,
) !void {
    try emit_storage_payload_ptr_with_indent(allocator, out, name, indent);
    try append_fmt(allocator, out, "{s}i32.const 4\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
}

pub fn emit_storage_data_ptr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try emit_storage_payload_ptr(allocator, out, name);
    try append_fmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "    i32.add\n");
}

/// data_base + index * elem_bytes (stack result is element address).
pub fn emit_storage_element_ptr_from_local(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    index_local: []const u8,
    elem_bytes: usize,
) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n", .{storage_local});
    try out.appendSlice(allocator, "    call $__arc_payload\n");
    try append_fmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "    i32.add\n");
    try append_fmt(allocator, out, "    local.get ${s}\n", .{index_local});
    if (elem_bytes != 1) {
        try append_fmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "    i32.mul\n");
    }
    try out.appendSlice(allocator, "    i32.add\n");
}

pub fn emit_storage_element_ptr_from_local_with_indent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    index_local: []const u8,
    elem_bytes: usize,
    indent: []const u8,
) !void {
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, storage_local });
    try append_fmt(allocator, out, "{s}call $__arc_payload\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, STORAGE_PAYLOAD_HEADER_BYTES });
    try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, index_local });
    if (elem_bytes != 1) {
        try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, elem_bytes });
        try append_fmt(allocator, out, "{s}i32.mul\n", .{indent});
    }
    try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
}

pub fn emit_storage_alias_protect(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    target_name: []const u8,
) !void {
    if (std.mem.eql(u8, source_name, target_name)) return;
    try append_fmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_inc\n");
    try out.appendSlice(allocator, "    drop\n");
}

pub fn emit_storage_alias_release(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    target_name: []const u8,
) !void {
    if (std.mem.eql(u8, source_name, target_name)) return;
    try append_fmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
}

/// Empty `[u8]`-style storage object (type_id = TYPE_ID_STORAGE_U8), handle left on stack.
/// Uses `$__storage_overwrite_tmp` as scratch (must be declared by caller locals).
pub fn emit_empty_storage_u8_value(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try emit_empty_storage_with_type_id(allocator, out, TYPE_ID_STORAGE_U8, "      ");
}

/// Empty storage with explicit type_id; handle left on stack via overwrite tmp.
pub fn emit_empty_storage_with_type_id(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    type_id: usize,
    indent: []const u8,
) !void {
    try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, STORAGE_PAYLOAD_HEADER_BYTES });
    try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, type_id });
    try append_fmt(allocator, out, "{s}call $__arc_alloc\n", .{indent});
    try append_fmt(allocator, out, "{s}local.set ${s}\n", .{ indent, STORAGE_OVERWRITE_TMP_LOCAL });
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, STORAGE_OVERWRITE_TMP_LOCAL });
    try append_fmt(allocator, out, "{s}call $__arc_payload\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.const 0\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.store\n", .{indent});
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, STORAGE_OVERWRITE_TMP_LOCAL });
    try append_fmt(allocator, out, "{s}call $__arc_payload\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.const 4\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.const 0\n", .{indent});
    try append_fmt(allocator, out, "{s}i32.store\n", .{indent});
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, STORAGE_OVERWRITE_TMP_LOCAL });
}

/// type_id for scheme-A vs managed storage elements (matches codegen storageTypeIdForElement policy for non-struct).
/// Managed-leaf Tuple packs use a dedicated layout type_id from codegen (not this helper).
pub fn storage_type_id_for_scalar_or_managed_elem(elem_ty: []const u8, treat_as_managed: bool) usize {
    if (treat_as_managed and type_util.storageElementByteWidth(elem_ty) == null and type_util.tupleScalarLeafStorageByteWidth(elem_ty) == null) {
        return TYPE_ID_STORAGE_MANAGED;
    }
    return TYPE_ID_STORAGE_U8;
}

test "storage payload header constants match memory layout" {
    try std.testing.expectEqual(@as(usize, 8), STORAGE_PAYLOAD_HEADER_BYTES);
    try std.testing.expectEqual(@as(usize, 1), TYPE_ID_STORAGE_U8);
    try std.testing.expectEqual(@as(usize, 65535), TYPE_ID_STORAGE_MANAGED);
}

test "emit_storage_cap_ptr offsets past len field" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit_storage_cap_ptr(std.testing.allocator, &out, "xs");
    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.get $xs") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call $__arc_payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.const 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.add") != null);
}

test "emit_storage_data_ptr skips 8-byte header" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit_storage_data_ptr(std.testing.allocator, &out, "xs");
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.const 8") != null);
}

test "emitStorageElementPtr multiplies non-unit element size" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit_storage_element_ptr_from_local(std.testing.allocator, &out, "xs", "i", 4);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.get $i") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.const 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.mul") != null);
}

test "emit_empty_storage_u8_value zeros len and cap" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit_empty_storage_u8_value(std.testing.allocator, &out);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call $__arc_alloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.const 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, STORAGE_OVERWRITE_TMP_LOCAL) != null);
}

test "alias protect is no-op when source equals target" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try emit_storage_alias_protect(std.testing.allocator, &out, "a", "a");
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}
