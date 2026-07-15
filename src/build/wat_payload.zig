const std = @import("std");
const type_util = @import("type_name.zig");

/// WAT emission for scalar payload load/store and scheme-A Tuple leaf pack.
/// Depends only on type_name + std — no LocalSet / CodegenContext / tokens.
pub const TUPLE_PACK_SPILL_I32 = "__tuple_pack_spill_i32";
pub const TUPLE_PACK_SPILL_I32_1 = "__tuple_pack_spill_i32_1";
pub const TUPLE_PACK_SPILL_I32_2 = "__tuple_pack_spill_i32_2";
pub const TUPLE_PACK_SPILL_I32_3 = "__tuple_pack_spill_i32_3";
pub const TUPLE_PACK_SPILL_I64 = "__tuple_pack_spill_i64";
pub const TUPLE_PACK_SPILL_F32 = "__tuple_pack_spill_f32";
pub const TUPLE_PACK_SPILL_F64 = "__tuple_pack_spill_f64";

pub fn wasm_type(ty: []const u8) []const u8 {
    if (std.mem.eql(u8, ty, "bool")) return "i32";
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) return "i32";
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) return "i32";
    if (std.mem.eql(u8, ty, "i32") or std.mem.eql(u8, ty, "u32")) return "i32";
    if (std.mem.eql(u8, ty, "isize") or std.mem.eql(u8, ty, "usize")) return "i32";
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) return "i64";
    if (std.mem.eql(u8, ty, "f32")) return "f32";
    if (std.mem.eql(u8, ty, "f64")) return "f64";
    return "i32";
}

pub fn tuple_pack_spill_local(ty: []const u8) []const u8 {
    return tuple_pack_spill_local_at(ty, 0);
}

/// Spill local for pack leaf `index` (0-based). Same wasm type needs distinct slots so
/// multi-leaf pop/push (managed inc) does not clobber earlier leaves.
pub fn tuple_pack_spill_local_at(ty: []const u8, index: usize) []const u8 {
    const wt = wasm_type(ty);
    if (std.mem.eql(u8, wt, "i64")) return TUPLE_PACK_SPILL_I64;
    if (std.mem.eql(u8, wt, "f32")) return TUPLE_PACK_SPILL_F32;
    if (std.mem.eql(u8, wt, "f64")) return TUPLE_PACK_SPILL_F64;
    return switch (index) {
        0 => TUPLE_PACK_SPILL_I32,
        1 => TUPLE_PACK_SPILL_I32_1,
        2 => TUPLE_PACK_SPILL_I32_2,
        else => TUPLE_PACK_SPILL_I32_3,
    };
}

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

pub fn append_store_for_payload_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) {
        try out.appendSlice(allocator, "    i32.store8\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) {
        try out.appendSlice(allocator, "    i32.store16\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try out.appendSlice(allocator, "    i64.store\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try out.appendSlice(allocator, "    f32.store\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try out.appendSlice(allocator, "    f64.store\n");
        return;
    }
    try out.appendSlice(allocator, "    i32.store\n");
}

pub fn append_store_for_payload_type_with_indent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) {
        try append_fmt(allocator, out, "{s}i32.store8\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) {
        try append_fmt(allocator, out, "{s}i32.store16\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try append_fmt(allocator, out, "{s}i64.store\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try append_fmt(allocator, out, "{s}f32.store\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try append_fmt(allocator, out, "{s}f64.store\n", .{indent});
        return;
    }
    try append_fmt(allocator, out, "{s}i32.store\n", .{indent});
}

pub fn append_load_for_payload_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8")) {
        try out.appendSlice(allocator, "    i32.load8_s\n");
        return;
    }
    if (std.mem.eql(u8, ty, "u8")) {
        try out.appendSlice(allocator, "    i32.load8_u\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i16")) {
        try out.appendSlice(allocator, "    i32.load16_s\n");
        return;
    }
    if (std.mem.eql(u8, ty, "u16")) {
        try out.appendSlice(allocator, "    i32.load16_u\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try out.appendSlice(allocator, "    i64.load\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try out.appendSlice(allocator, "    f32.load\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try out.appendSlice(allocator, "    f64.load\n");
        return;
    }
    try out.appendSlice(allocator, "    i32.load\n");
}

pub fn append_load_for_payload_type_with_indent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8")) {
        try append_fmt(allocator, out, "{s}i32.load8_s\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "u8")) {
        try append_fmt(allocator, out, "{s}i32.load8_u\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i16")) {
        try append_fmt(allocator, out, "{s}i32.load16_s\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "u16")) {
        try append_fmt(allocator, out, "{s}i32.load16_u\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try append_fmt(allocator, out, "{s}i64.load\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try append_fmt(allocator, out, "{s}f32.load\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try append_fmt(allocator, out, "{s}f64.load\n", .{indent});
        return;
    }
    try append_fmt(allocator, out, "{s}i32.load\n", .{indent});
}

/// Stack holds leaf0..leafN-1 (top = last). Spill reverse into memory at base_local + leaf offsets.
/// Managed payload leaves pack as i32 handles (scheme A).
pub fn append_store_tuple_scalar_leaves_from_stack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    type_util.append_tuple_leaf_types(allocator, tuple_ty, &leaf_types) catch return error.UnsupportedLowering;
    if (leaf_types.items.len == 0) return error.UnsupportedLowering;

    var offsets = try allocator.alloc(usize, leaf_types.items.len);
    defer allocator.free(offsets);
    var offset: usize = 0;
    for (leaf_types.items, 0..) |leaf_ty, i| {
        if (!type_util.is_tuple_packable_leaf_type(leaf_ty)) {
            return error.UnsupportedTupleStorageLeaf;
        }
        offsets[i] = offset;
        offset += type_util.type_payload_bytes(leaf_ty);
    }

    var i = leaf_types.items.len;
    while (i > 0) {
        i -= 1;
        const leaf_ty = leaf_types.items[i];
        const spill = tuple_pack_spill_local(leaf_ty);
        try append_fmt(allocator, out, "{s}local.set ${s}\n", .{ indent, spill });
        try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
        if (offsets[i] != 0) {
            try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offsets[i] });
            try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
        }
        try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, spill });
        try append_store_for_payload_type_with_indent(allocator, out, leaf_ty, indent);
    }
}

/// Load packed leaves from base_local + offsets onto the stack (leaf0..leafN-1).
/// Managed payload leaves load as i32 handles; caller decides whether to `__arc_inc`.
pub fn append_load_tuple_scalar_leaves_to_stack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    type_util.append_tuple_leaf_types(allocator, tuple_ty, &leaf_types) catch return error.UnsupportedLowering;
    if (leaf_types.items.len == 0) return error.UnsupportedLowering;

    var offset: usize = 0;
    for (leaf_types.items) |leaf_ty| {
        if (!type_util.is_tuple_packable_leaf_type(leaf_ty)) {
            return error.UnsupportedTupleStorageLeaf;
        }
        try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
        if (offset != 0) {
            try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
            try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
        }
        try append_load_for_payload_type_with_indent(allocator, out, leaf_ty, indent);
        offset += type_util.type_payload_bytes(leaf_ty);
    }
}

/// After leaves are on stack (leaf0..leafN-1, top = last), inc each managed payload leaf in place.
/// Uses spill temps; stack order preserved.
pub fn append_inc_managed_tuple_leaves_on_stack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    indent: []const u8,
) !void {
    if (!type_util.tuple_has_managed_pack_leaf(tuple_ty)) return;
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    type_util.append_tuple_leaf_types(allocator, tuple_ty, &leaf_types) catch return error.UnsupportedLowering;
    if (leaf_types.items.len == 0) return;

    var spills = try allocator.alloc([]const u8, leaf_types.items.len);
    defer allocator.free(spills);
    var i = leaf_types.items.len;
    while (i > 0) {
        i -= 1;
        const leaf_ty = leaf_types.items[i];
        // Per-leaf spill slot: text+u8 both lower to i32 and must not share one temp.
        const spill = tuple_pack_spill_local_at(leaf_ty, i);
        spills[i] = spill;
        try append_fmt(allocator, out, "{s}local.set ${s}\n", .{ indent, spill });
    }
    for (leaf_types.items, 0..) |leaf_ty, idx| {
        try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, spills[idx] });
        if (type_util.is_managed_payload_type(leaf_ty)) {
            try append_fmt(allocator, out, "{s};; tuple-pack-managed-leaf-inc\n", .{indent});
            try append_fmt(allocator, out, "{s}call $__arc_inc\n", .{indent});
        }
    }
}

/// Load a single direct (non-nested-expand) element from packed tuple base.
/// Nested Tuple elements push all flattened leaves of that element.
pub fn append_load_tuple_element_from_packed_base(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    elem_index: usize,
    base_local: []const u8,
    indent: []const u8,
) !void {
    const elem_ty = type_util.tuple_element_type_at(tuple_ty, elem_index) orelse return error.UnsupportedLowering;
    const elem_offset = type_util.tuple_element_pack_offset(tuple_ty, elem_index) orelse return error.UnsupportedLowering;
    if (type_util.is_tuple_type_name(elem_ty)) {
        if (elem_offset != 0) {
            try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
            try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, elem_offset });
            try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
            try append_fmt(allocator, out, "{s}local.set ${s}\n", .{ indent, base_local });
        }
        try append_load_tuple_scalar_leaves_to_stack(allocator, out, elem_ty, base_local, indent);
        return;
    }
    if (!type_util.is_tuple_packable_leaf_type(elem_ty)) return error.UnsupportedTupleStorageLeaf;
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
    if (elem_offset != 0) {
        try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, elem_offset });
        try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
    }
    try append_load_for_payload_type_with_indent(allocator, out, elem_ty, indent);
}

pub fn append_store_payload_or_tuple_from_stack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    if (type_util.is_tuple_type_name(elem_ty)) {
        try append_store_tuple_scalar_leaves_from_stack(allocator, out, elem_ty, base_local, indent);
        return;
    }
    if (indent.len == 0 or std.mem.eql(u8, indent, "    ")) {
        try append_store_for_payload_type(allocator, out, elem_ty);
    } else {
        try append_store_for_payload_type_with_indent(allocator, out, elem_ty, indent);
    }
}

pub fn append_load_payload_or_tuple_to_stack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    if (type_util.is_tuple_type_name(elem_ty)) {
        try append_load_tuple_scalar_leaves_to_stack(allocator, out, elem_ty, base_local, indent);
        return;
    }
    try append_fmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
    if (indent.len == 0 or std.mem.eql(u8, indent, "    ")) {
        try append_load_for_payload_type(allocator, out, elem_ty);
    } else {
        try append_load_for_payload_type_with_indent(allocator, out, elem_ty, indent);
    }
}

test "payload store/load wat for i32" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try append_store_for_payload_type(std.testing.allocator, &out, "i32");
    try std.testing.expectEqualStrings("    i32.store\n", out.items);
    out.clearRetainingCapacity();
    try append_load_for_payload_type(std.testing.allocator, &out, "u8");
    try std.testing.expectEqualStrings("    i32.load8_u\n", out.items);
}

test "tuple pack spill local names follow wasm type" {
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_I32, tuple_pack_spill_local("i32"));
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_I64, tuple_pack_spill_local("i64"));
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_F32, tuple_pack_spill_local("f32"));
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_F64, tuple_pack_spill_local("f64"));
}

test "tuple scalar leaf store emits spill and store sequence" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try append_store_tuple_scalar_leaves_from_stack(
        std.testing.allocator,
        &out,
        "Tuple<i32,u8>",
        "base",
        "    ",
    );
    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.set $__tuple_pack_spill_i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.get $base") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.store8") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.store\n") != null);
}

test "managed leaf tuple pack stores i32 handle and u8" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try append_store_tuple_scalar_leaves_from_stack(
        std.testing.allocator,
        &out,
        "Tuple<text,u8>",
        "base",
        "    ",
    );
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.store8") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.store\n") != null);
}

test "load single tuple element from packed base" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try append_load_tuple_element_from_packed_base(
        std.testing.allocator,
        &out,
        "Tuple<i32,u8>",
        1,
        "base",
        "    ",
    );
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.const 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i32.load8_u") != null);
}
