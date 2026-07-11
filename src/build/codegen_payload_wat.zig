const std = @import("std");
const type_util = @import("type_name.zig");

/// WAT emission for scalar payload load/store and scheme-A Tuple leaf pack.
/// Depends only on type_name + std — no LocalSet / CodegenContext / tokens.
pub const TUPLE_PACK_SPILL_I32 = "__tuple_pack_spill_i32";
pub const TUPLE_PACK_SPILL_I64 = "__tuple_pack_spill_i64";
pub const TUPLE_PACK_SPILL_F32 = "__tuple_pack_spill_f32";
pub const TUPLE_PACK_SPILL_F64 = "__tuple_pack_spill_f64";

pub fn wasmType(ty: []const u8) []const u8 {
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

pub fn tuplePackSpillLocal(ty: []const u8) []const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, wt, "i64")) return TUPLE_PACK_SPILL_I64;
    if (std.mem.eql(u8, wt, "f32")) return TUPLE_PACK_SPILL_F32;
    if (std.mem.eql(u8, wt, "f64")) return TUPLE_PACK_SPILL_F64;
    return TUPLE_PACK_SPILL_I32;
}

fn appendFmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

pub fn appendStoreForPayloadType(
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

pub fn appendStoreForPayloadTypeWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) {
        try appendFmt(allocator, out, "{s}i32.store8\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) {
        try appendFmt(allocator, out, "{s}i32.store16\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try appendFmt(allocator, out, "{s}i64.store\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try appendFmt(allocator, out, "{s}f32.store\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try appendFmt(allocator, out, "{s}f64.store\n", .{indent});
        return;
    }
    try appendFmt(allocator, out, "{s}i32.store\n", .{indent});
}

pub fn appendLoadForPayloadType(
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

pub fn appendLoadForPayloadTypeWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8")) {
        try appendFmt(allocator, out, "{s}i32.load8_s\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "u8")) {
        try appendFmt(allocator, out, "{s}i32.load8_u\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i16")) {
        try appendFmt(allocator, out, "{s}i32.load16_s\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "u16")) {
        try appendFmt(allocator, out, "{s}i32.load16_u\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try appendFmt(allocator, out, "{s}i64.load\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try appendFmt(allocator, out, "{s}f32.load\n", .{indent});
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try appendFmt(allocator, out, "{s}f64.load\n", .{indent});
        return;
    }
    try appendFmt(allocator, out, "{s}i32.load\n", .{indent});
}

/// Stack holds leaf0..leafN-1 (top = last). Spill reverse into memory at base_local + leaf offsets.
pub fn appendStoreTupleScalarLeavesFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    type_util.appendTupleLeafTypes(allocator, tuple_ty, &leaf_types) catch return error.UnsupportedLowering;
    if (leaf_types.items.len == 0) return error.UnsupportedLowering;

    var offsets = try allocator.alloc(usize, leaf_types.items.len);
    defer allocator.free(offsets);
    var offset: usize = 0;
    for (leaf_types.items, 0..) |leaf_ty, i| {
        if (!type_util.isCoreWasmScalar(leaf_ty) or type_util.isManagedPayloadType(leaf_ty)) {
            return error.UnsupportedLowering;
        }
        offsets[i] = offset;
        offset += type_util.typePayloadBytes(leaf_ty);
    }

    var i = leaf_types.items.len;
    while (i > 0) {
        i -= 1;
        const leaf_ty = leaf_types.items[i];
        const spill = tuplePackSpillLocal(leaf_ty);
        try appendFmt(allocator, out, "{s}local.set ${s}\n", .{ indent, spill });
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
        if (offsets[i] != 0) {
            try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offsets[i] });
            try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
        }
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, spill });
        try appendStoreForPayloadTypeWithIndent(allocator, out, leaf_ty, indent);
    }
}

/// Load packed scalar leaves from base_local + offsets onto the stack (leaf0..leafN-1).
pub fn appendLoadTupleScalarLeavesToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    type_util.appendTupleLeafTypes(allocator, tuple_ty, &leaf_types) catch return error.UnsupportedLowering;
    if (leaf_types.items.len == 0) return error.UnsupportedLowering;

    var offset: usize = 0;
    for (leaf_types.items) |leaf_ty| {
        if (!type_util.isCoreWasmScalar(leaf_ty) or type_util.isManagedPayloadType(leaf_ty)) {
            return error.UnsupportedLowering;
        }
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
        if (offset != 0) {
            try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
            try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
        }
        try appendLoadForPayloadTypeWithIndent(allocator, out, leaf_ty, indent);
        offset += type_util.typePayloadBytes(leaf_ty);
    }
}

pub fn appendStorePayloadOrTupleFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    if (type_util.isTupleTypeName(elem_ty)) {
        try appendStoreTupleScalarLeavesFromStack(allocator, out, elem_ty, base_local, indent);
        return;
    }
    if (indent.len == 0 or std.mem.eql(u8, indent, "    ")) {
        try appendStoreForPayloadType(allocator, out, elem_ty);
    } else {
        try appendStoreForPayloadTypeWithIndent(allocator, out, elem_ty, indent);
    }
}

pub fn appendLoadPayloadOrTupleToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) !void {
    if (type_util.isTupleTypeName(elem_ty)) {
        try appendLoadTupleScalarLeavesToStack(allocator, out, elem_ty, base_local, indent);
        return;
    }
    try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
    if (indent.len == 0 or std.mem.eql(u8, indent, "    ")) {
        try appendLoadForPayloadType(allocator, out, elem_ty);
    } else {
        try appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, indent);
    }
}

test "payload store/load wat for i32" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try appendStoreForPayloadType(std.testing.allocator, &out, "i32");
    try std.testing.expectEqualStrings("    i32.store\n", out.items);
    out.clearRetainingCapacity();
    try appendLoadForPayloadType(std.testing.allocator, &out, "u8");
    try std.testing.expectEqualStrings("    i32.load8_u\n", out.items);
}

test "tuple pack spill local names follow wasm type" {
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_I32, tuplePackSpillLocal("i32"));
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_I64, tuplePackSpillLocal("i64"));
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_F32, tuplePackSpillLocal("f32"));
    try std.testing.expectEqualStrings(TUPLE_PACK_SPILL_F64, tuplePackSpillLocal("f64"));
}

test "tuple scalar leaf store emits spill and store sequence" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try appendStoreTupleScalarLeavesFromStack(
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

test "managed leaf tuple pack is UnsupportedLowering" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    const err = appendStoreTupleScalarLeavesFromStack(
        std.testing.allocator,
        &out,
        "Tuple<text,u8>",
        "base",
        "    ",
    );
    try std.testing.expectError(error.UnsupportedLowering, err);
}
