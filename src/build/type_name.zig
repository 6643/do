const std = @import("std");

/// Shared type-name parsing and pure layout helpers for generic / Tuple / scalar / storage forms.
/// No codegen or sema dependencies — string-level only.
pub const GenericTypeArgsRange = struct {
    base: []const u8,
    args: []const u8,
};

pub fn genericTypeArgsRange(ty: []const u8) ?GenericTypeArgsRange {
    var open_idx: ?usize = null;
    var depth: usize = 0;
    for (ty, 0..) |ch, idx| {
        if (ch == '<') {
            if (depth == 0 and open_idx == null) open_idx = idx;
            depth += 1;
            continue;
        }
        if (ch == '>') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0 and idx + 1 != ty.len) return null;
        }
    }
    if (depth != 0) return null;
    const open = open_idx orelse return null;
    if (ty.len == 0 or ty[ty.len - 1] != '>') return null;
    return .{
        .base = ty[0..open],
        .args = ty[open + 1 .. ty.len - 1],
    };
}

pub fn findTopLevelTypeSeparatorFrom(ty: []const u8, start_idx: usize, sep: u8) ?usize {
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;
    var depth_paren: usize = 0;
    var i = start_idx;
    while (i < ty.len) : (i += 1) {
        switch (ty[i]) {
            '<' => depth_angle += 1,
            '>' => {
                if (depth_angle > 0) depth_angle -= 1;
            },
            '[' => depth_bracket += 1,
            ']' => {
                if (depth_bracket > 0) depth_bracket -= 1;
            },
            '(' => depth_paren += 1,
            ')' => {
                if (depth_paren > 0) depth_paren -= 1;
            },
            else => {},
        }
        if (depth_angle == 0 and depth_bracket == 0 and depth_paren == 0 and ty[i] == sep) return i;
    }
    return null;
}

pub fn genericTypeArgAt(concrete_ty: []const u8, target_idx: usize) ?[]const u8 {
    const args = genericTypeArgsRange(concrete_ty) orelse return null;
    var arg_start: usize = 0;
    var arg_idx: usize = 0;
    while (arg_start < args.args.len) {
        const arg_end = findTopLevelTypeSeparatorFrom(args.args, arg_start, ',') orelse args.args.len;
        if (arg_start == arg_end) return null;
        if (arg_idx == target_idx) return args.args[arg_start..arg_end];
        arg_idx += 1;
        arg_start = arg_end;
        if (arg_start < args.args.len) arg_start += 1;
    }
    return null;
}

pub fn typeBaseName(ty: []const u8) []const u8 {
    for (ty, 0..) |ch, idx| {
        if (ch == '<') return ty[0..idx];
    }
    return ty;
}

pub fn isTupleTypeName(ty: []const u8) bool {
    const args = genericTypeArgsRange(ty) orelse return false;
    return std.mem.eql(u8, args.base, "Tuple");
}

pub fn tupleArity(tuple_ty: []const u8) ?usize {
    const args = genericTypeArgsRange(tuple_ty) orelse return null;
    if (!std.mem.eql(u8, args.base, "Tuple")) return null;
    var count: usize = 0;
    var arg_start: usize = 0;
    while (arg_start < args.args.len) {
        const arg_end = findTopLevelTypeSeparatorFrom(args.args, arg_start, ',') orelse args.args.len;
        if (arg_start == arg_end) return null;
        count += 1;
        arg_start = arg_end;
        if (arg_start < args.args.len) arg_start += 1;
    }
    return count;
}

pub fn tupleElementTypeAt(tuple_ty: []const u8, idx: usize) ?[]const u8 {
    if (!isTupleTypeName(tuple_ty)) return null;
    return genericTypeArgAt(tuple_ty, idx);
}

/// Flatten nested Tuple leaves into `out` (type name views into `tuple_ty`).
pub fn appendTupleLeafTypes(
    allocator: std.mem.Allocator,
    tuple_ty: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    const arity = tupleArity(tuple_ty) orelse return error.InvalidTypeRef;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.InvalidTypeRef;
        if (isTupleTypeName(elem_ty)) {
            try appendTupleLeafTypes(allocator, elem_ty, out);
        } else {
            try out.append(allocator, elem_ty);
        }
    }
}

// --- Scalar / storage classification (shared by sema + codegen) ---

pub fn isIntegerTypeName(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "i32") or
        std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u8") or std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "u32") or std.mem.eql(u8, ty, "u64") or std.mem.eql(u8, ty, "isize") or
        std.mem.eql(u8, ty, "usize");
}

pub fn isFloatTypeName(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "f32") or std.mem.eql(u8, ty, "f64");
}

pub fn isCoreIntegerScalar(ty: []const u8) bool {
    return isIntegerTypeName(ty);
}

pub fn isCoreFloatScalar(ty: []const u8) bool {
    return isFloatTypeName(ty);
}

pub fn isCoreWasmScalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "bool") or isIntegerTypeName(ty) or isFloatTypeName(ty);
}

pub fn isStorageTypeName(ty: []const u8) bool {
    return ty.len >= 3 and ty[0] == '[' and ty[ty.len - 1] == ']';
}

pub fn storageElemTypeFromName(ty: []const u8) ?[]const u8 {
    if (!isStorageTypeName(ty)) return null;
    return ty[1 .. ty.len - 1];
}

pub fn managedPayloadElemTypeFromName(ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, ty, "text")) return "u8";
    return storageElemTypeFromName(ty);
}

pub fn isManagedPayloadType(ty: []const u8) bool {
    return managedPayloadElemTypeFromName(ty) != null;
}

pub fn typePayloadBytes(ty: []const u8) usize {
    if (isManagedPayloadType(ty)) return 4;
    if (std.mem.eql(u8, ty, "bool")) return 4;
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) return 1;
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) return 2;
    if (std.mem.eql(u8, ty, "i32") or std.mem.eql(u8, ty, "u32")) return 4;
    if (std.mem.eql(u8, ty, "isize") or std.mem.eql(u8, ty, "usize")) return 4;
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) return 8;
    if (std.mem.eql(u8, ty, "f32")) return 4;
    if (std.mem.eql(u8, ty, "f64")) return 8;
    return 4;
}

pub fn typePayloadAlignment(ty: []const u8) usize {
    return @min(typePayloadBytes(ty), 4);
}

/// Byte width of a scheme-A packable storage element (scalar only). Nested/managed return null.
pub fn storageElementByteWidth(elem_ty: []const u8) ?usize {
    if (std.mem.eql(u8, elem_ty, "i8") or std.mem.eql(u8, elem_ty, "u8")) return 1;
    if (std.mem.eql(u8, elem_ty, "i16") or std.mem.eql(u8, elem_ty, "u16")) return 2;
    if (std.mem.eql(u8, elem_ty, "i64") or std.mem.eql(u8, elem_ty, "u64")) return 8;
    if (std.mem.eql(u8, elem_ty, "f64")) return 8;
    if (std.mem.eql(u8, elem_ty, "bool")) return 4;
    if (std.mem.eql(u8, elem_ty, "i32") or std.mem.eql(u8, elem_ty, "u32")) return 4;
    if (std.mem.eql(u8, elem_ty, "isize") or std.mem.eql(u8, elem_ty, "usize")) return 4;
    if (std.mem.eql(u8, elem_ty, "f32")) return 4;
    return null;
}

/// Known scalar/nested-storage element → concrete `[T]` / `[[T]]` type name.
pub fn storageTypeNameForElem(elem_ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, elem_ty, "bool")) return "[bool]";
    if (std.mem.eql(u8, elem_ty, "i8")) return "[i8]";
    if (std.mem.eql(u8, elem_ty, "u8")) return "[u8]";
    if (std.mem.eql(u8, elem_ty, "i16")) return "[i16]";
    if (std.mem.eql(u8, elem_ty, "u16")) return "[u16]";
    if (std.mem.eql(u8, elem_ty, "i32")) return "[i32]";
    if (std.mem.eql(u8, elem_ty, "u32")) return "[u32]";
    if (std.mem.eql(u8, elem_ty, "isize")) return "[isize]";
    if (std.mem.eql(u8, elem_ty, "usize")) return "[usize]";
    if (std.mem.eql(u8, elem_ty, "i64")) return "[i64]";
    if (std.mem.eql(u8, elem_ty, "u64")) return "[u64]";
    if (std.mem.eql(u8, elem_ty, "f32")) return "[f32]";
    if (std.mem.eql(u8, elem_ty, "f64")) return "[f64]";
    if (std.mem.eql(u8, elem_ty, "[bool]")) return "[[bool]]";
    if (std.mem.eql(u8, elem_ty, "[i8]")) return "[[i8]]";
    if (std.mem.eql(u8, elem_ty, "[u8]")) return "[[u8]]";
    if (std.mem.eql(u8, elem_ty, "[i16]")) return "[[i16]]";
    if (std.mem.eql(u8, elem_ty, "[u16]")) return "[[u16]]";
    if (std.mem.eql(u8, elem_ty, "[i32]")) return "[[i32]]";
    if (std.mem.eql(u8, elem_ty, "[u32]")) return "[[u32]]";
    if (std.mem.eql(u8, elem_ty, "[isize]")) return "[[isize]]";
    if (std.mem.eql(u8, elem_ty, "[usize]")) return "[[usize]]";
    if (std.mem.eql(u8, elem_ty, "[i64]")) return "[[i64]]";
    if (std.mem.eql(u8, elem_ty, "[u64]")) return "[[u64]]";
    if (std.mem.eql(u8, elem_ty, "[f32]")) return "[[f32]]";
    if (std.mem.eql(u8, elem_ty, "[f64]")) return "[[f64]]";
    return null;
}

/// Whether a Tuple leaf can be packed into scheme-A storage (core scalar or managed payload handle).
pub fn isTuplePackableLeafType(elem_ty: []const u8) bool {
    if (isManagedPayloadType(elem_ty)) return true;
    return isCoreWasmScalar(elem_ty);
}

/// Scheme A: packed Tuple storage width. Nested Tuple flattens; managed payload leaves pack as 4-byte handles.
/// Non-packable leaves (e.g. bare struct values) → null.
pub fn tupleScalarLeafStorageByteWidth(tuple_ty: []const u8) ?usize {
    if (!isTupleTypeName(tuple_ty)) return null;
    const arity = tupleArity(tuple_ty) orelse return null;
    var total: usize = 0;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return null;
        if (isTupleTypeName(elem_ty)) {
            total += tupleScalarLeafStorageByteWidth(elem_ty) orelse return null;
            continue;
        }
        if (!isTuplePackableLeafType(elem_ty)) return null;
        total += typePayloadBytes(elem_ty);
    }
    return total;
}

/// True when any flattened leaf is a managed payload (text / [T] handle).
pub fn tupleHasManagedPackLeaf(tuple_ty: []const u8) bool {
    if (!isTupleTypeName(tuple_ty)) return false;
    const arity = tupleArity(tuple_ty) orelse return false;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return false;
        if (isTupleTypeName(elem_ty)) {
            if (tupleHasManagedPackLeaf(elem_ty)) return true;
            continue;
        }
        if (isManagedPayloadType(elem_ty)) return true;
    }
    return false;
}

/// Byte offset of direct element `index` inside a packed Tuple (not flattened).
pub fn tupleElementPackOffset(tuple_ty: []const u8, index: usize) ?usize {
    if (!isTupleTypeName(tuple_ty)) return null;
    const arity = tupleArity(tuple_ty) orelse return null;
    if (index >= arity) return null;
    var offset: usize = 0;
    var idx: usize = 0;
    while (idx < index) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return null;
        if (isTupleTypeName(elem_ty)) {
            offset += tupleScalarLeafStorageByteWidth(elem_ty) orelse return null;
        } else if (isTuplePackableLeafType(elem_ty)) {
            offset += typePayloadBytes(elem_ty);
        } else {
            return null;
        }
    }
    return offset;
}

test "tuple type name helpers" {
    try std.testing.expect(isTupleTypeName("Tuple<i32,bool>"));
    try std.testing.expect(!isTupleTypeName("Pair<i32,bool>"));
    try std.testing.expectEqual(@as(?usize, 2), tupleArity("Tuple<i32,bool>"));
    try std.testing.expectEqualStrings("i32", tupleElementTypeAt("Tuple<i32,bool>", 0).?);
    try std.testing.expectEqualStrings("bool", tupleElementTypeAt("Tuple<i32,bool>", 1).?);
    try std.testing.expectEqualStrings("Tuple", typeBaseName("Tuple<i32,bool>"));

    var leaves = std.ArrayList([]const u8).empty;
    defer leaves.deinit(std.testing.allocator);
    try appendTupleLeafTypes(std.testing.allocator, "Tuple<Tuple<i32,u8>,bool>", &leaves);
    try std.testing.expectEqual(@as(usize, 3), leaves.items.len);
    try std.testing.expectEqualStrings("i32", leaves.items[0]);
    try std.testing.expectEqualStrings("u8", leaves.items[1]);
    try std.testing.expectEqualStrings("bool", leaves.items[2]);
}

test "scalar and storage type helpers" {
    try std.testing.expect(isIntegerTypeName("i32"));
    try std.testing.expect(isFloatTypeName("f64"));
    try std.testing.expect(isCoreWasmScalar("bool"));
    try std.testing.expect(!isCoreWasmScalar("text"));
    try std.testing.expect(isManagedPayloadType("text"));
    try std.testing.expect(isManagedPayloadType("[u8]"));
    try std.testing.expect(!isManagedPayloadType("i32"));
    try std.testing.expectEqual(@as(usize, 4), typePayloadBytes("i32"));
    try std.testing.expectEqual(@as(usize, 1), typePayloadBytes("u8"));
    try std.testing.expectEqual(@as(?usize, 4), storageElementByteWidth("i32"));
    try std.testing.expectEqualStrings("[u8]", storageTypeNameForElem("u8").?);
    try std.testing.expectEqual(@as(?usize, 5), tupleScalarLeafStorageByteWidth("Tuple<i32,u8>"));
    try std.testing.expectEqual(@as(?usize, 5), tupleScalarLeafStorageByteWidth("Tuple<text,u8>"));
    try std.testing.expect(tupleHasManagedPackLeaf("Tuple<text,u8>"));
    try std.testing.expect(!tupleHasManagedPackLeaf("Tuple<i32,u8>"));
    try std.testing.expectEqual(@as(?usize, 0), tupleElementPackOffset("Tuple<i32,u8>", 0));
    try std.testing.expectEqual(@as(?usize, 4), tupleElementPackOffset("Tuple<i32,u8>", 1));
    try std.testing.expectEqual(@as(?usize, 6), tupleScalarLeafStorageByteWidth("Tuple<Tuple<i32,u8>,u8>"));
}

test "tuple packable leaf and non-packable storage width table" {
    // Packable leaves: core scalars + managed payload handles.
    try std.testing.expect(isTuplePackableLeafType("i32"));
    try std.testing.expect(isTuplePackableLeafType("u8"));
    try std.testing.expect(isTuplePackableLeafType("bool"));
    try std.testing.expect(isTuplePackableLeafType("f64"));
    try std.testing.expect(isTuplePackableLeafType("text"));
    try std.testing.expect(isTuplePackableLeafType("[u8]"));
    // Bare user struct names are not packable leaves (scheme A boundary).
    try std.testing.expect(!isTuplePackableLeafType("Point"));
    try std.testing.expect(!isTuplePackableLeafType("PairBox"));
    // Width: packable ok; non-packable leaf → null (drives UnsupportedTupleStorageLeaf).
    try std.testing.expectEqual(@as(?usize, 5), tupleScalarLeafStorageByteWidth("Tuple<i32,u8>"));
    try std.testing.expectEqual(@as(?usize, 5), tupleScalarLeafStorageByteWidth("Tuple<text,u8>"));
    try std.testing.expectEqual(@as(?usize, 8), tupleScalarLeafStorageByteWidth("Tuple<text,[u8]>"));
    try std.testing.expect(tupleScalarLeafStorageByteWidth("Tuple<Point,u8>") == null);
    try std.testing.expect(tupleScalarLeafStorageByteWidth("Tuple<i32,Point>") == null);
    // Offsets sum preceding packable widths; a non-packable *preceding* leaf nulls later offsets.
    try std.testing.expectEqual(@as(?usize, 0), tupleElementPackOffset("Tuple<Point,u8>", 0));
    try std.testing.expect(tupleElementPackOffset("Tuple<Point,u8>", 1) == null);
    try std.testing.expectEqual(@as(?usize, 4), tupleElementPackOffset("Tuple<i32,Point>", 1));
    try std.testing.expectEqual(@as(?usize, 0), tupleElementPackOffset("Tuple<text,u8>", 0));
    try std.testing.expectEqual(@as(?usize, 4), tupleElementPackOffset("Tuple<text,u8>", 1));
}
