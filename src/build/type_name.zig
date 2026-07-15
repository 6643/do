const std = @import("std");

/// Shared type-name parsing and pure layout helpers for generic / Tuple / scalar / storage forms.
/// No codegen or sema dependencies — string-level only.
pub const GenericTypeArgsRange = struct {
    base: []const u8,
    args: []const u8,
};

pub fn generic_type_args_range(ty: []const u8) ?GenericTypeArgsRange {
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

pub fn find_top_level_type_separator_from(ty: []const u8, start_idx: usize, sep: u8) ?usize {
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

pub fn generic_type_arg_at(concrete_ty: []const u8, target_idx: usize) ?[]const u8 {
    const args = generic_type_args_range(concrete_ty) orelse return null;
    var arg_start: usize = 0;
    var arg_idx: usize = 0;
    while (arg_start < args.args.len) {
        const arg_end = find_top_level_type_separator_from(args.args, arg_start, ',') orelse args.args.len;
        if (arg_start == arg_end) return null;
        if (arg_idx == target_idx) return args.args[arg_start..arg_end];
        arg_idx += 1;
        arg_start = arg_end;
        if (arg_start < args.args.len) arg_start += 1;
    }
    return null;
}

pub fn type_base_name(ty: []const u8) []const u8 {
    for (ty, 0..) |ch, idx| {
        if (ch == '<') return ty[0..idx];
    }
    return ty;
}

pub fn is_tuple_type_name(ty: []const u8) bool {
    const args = generic_type_args_range(ty) orelse return false;
    return std.mem.eql(u8, args.base, "Tuple");
}

pub fn tuple_arity(tuple_ty: []const u8) ?usize {
    const args = generic_type_args_range(tuple_ty) orelse return null;
    if (!std.mem.eql(u8, args.base, "Tuple")) return null;
    var count: usize = 0;
    var arg_start: usize = 0;
    while (arg_start < args.args.len) {
        const arg_end = find_top_level_type_separator_from(args.args, arg_start, ',') orelse args.args.len;
        if (arg_start == arg_end) return null;
        count += 1;
        arg_start = arg_end;
        if (arg_start < args.args.len) arg_start += 1;
    }
    return count;
}

pub fn tuple_element_type_at(tuple_ty: []const u8, idx: usize) ?[]const u8 {
    if (!is_tuple_type_name(tuple_ty)) return null;
    return generic_type_arg_at(tuple_ty, idx);
}

/// Flatten nested Tuple leaves into `out` (type name views into `tuple_ty`).
pub fn append_tuple_leaf_types(
    allocator: std.mem.Allocator,
    tuple_ty: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    const arity = tuple_arity(tuple_ty) orelse return error.InvalidTypeRef;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return error.InvalidTypeRef;
        if (is_tuple_type_name(elem_ty)) {
            try append_tuple_leaf_types(allocator, elem_ty, out);
        } else {
            try out.append(allocator, elem_ty);
        }
    }
}

// --- Scalar / storage classification (shared by sema + codegen) ---

pub fn is_integer_type_name(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "i32") or
        std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u8") or std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "u32") or std.mem.eql(u8, ty, "u64") or std.mem.eql(u8, ty, "isize") or
        std.mem.eql(u8, ty, "usize");
}

pub fn is_float_type_name(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "f32") or std.mem.eql(u8, ty, "f64");
}

pub fn is_core_integer_scalar(ty: []const u8) bool {
    return is_integer_type_name(ty);
}

pub fn is_core_float_scalar(ty: []const u8) bool {
    return is_float_type_name(ty);
}

pub fn is_core_wasm_scalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "bool") or is_integer_type_name(ty) or is_float_type_name(ty);
}

pub fn is_storage_type_name(ty: []const u8) bool {
    return ty.len >= 3 and ty[0] == '[' and ty[ty.len - 1] == ']';
}

pub fn storage_elem_type_from_name(ty: []const u8) ?[]const u8 {
    if (!is_storage_type_name(ty)) return null;
    return ty[1 .. ty.len - 1];
}

pub fn managed_payload_elem_type_from_name(ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, ty, "text")) return "u8";
    return storage_elem_type_from_name(ty);
}

pub fn is_managed_payload_type(ty: []const u8) bool {
    return managed_payload_elem_type_from_name(ty) != null;
}

pub fn type_payload_bytes(ty: []const u8) usize {
    if (is_managed_payload_type(ty)) return 4;
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

pub fn type_payload_alignment(ty: []const u8) usize {
    return @min(type_payload_bytes(ty), 4);
}

/// Byte width of a scheme-A packable storage element (scalar only). Nested/managed return null.
pub fn storage_element_byte_width(elem_ty: []const u8) ?usize {
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
pub fn storage_type_name_for_elem(elem_ty: []const u8) ?[]const u8 {
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

/// Whether a terminal pack leaf is scalar or managed handle (not Tuple/struct names).
/// Pure-scalar struct slots are resolved in codegen with the struct table (nested sub-layout).
pub fn is_tuple_packable_leaf_type(elem_ty: []const u8) bool {
    if (is_managed_payload_type(elem_ty)) return true;
    return is_core_wasm_scalar(elem_ty);
}

/// Scheme A: packed Tuple storage width for scalar/managed/nested-Tuple only (no struct table).
/// Pure-scalar struct direct slots use codegen `tuple_pack_width_with_structs`. Nested Tuple is a sub-tree
/// (contiguous subregion), not a language-level flatten to a flat Tuple type.
pub fn tuple_scalar_leaf_storage_byte_width(tuple_ty: []const u8) ?usize {
    if (!is_tuple_type_name(tuple_ty)) return null;
    const arity = tuple_arity(tuple_ty) orelse return null;
    var total: usize = 0;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return null;
        if (is_tuple_type_name(elem_ty)) {
            total += tuple_scalar_leaf_storage_byte_width(elem_ty) orelse return null;
            continue;
        }
        if (!is_tuple_packable_leaf_type(elem_ty)) return null;
        total += type_payload_bytes(elem_ty);
    }
    return total;
}

/// True when any flattened leaf is a managed payload (text / [T] handle).
pub fn tuple_has_managed_pack_leaf(tuple_ty: []const u8) bool {
    if (!is_tuple_type_name(tuple_ty)) return false;
    const arity = tuple_arity(tuple_ty) orelse return false;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return false;
        if (is_tuple_type_name(elem_ty)) {
            if (tuple_has_managed_pack_leaf(elem_ty)) return true;
            continue;
        }
        if (is_managed_payload_type(elem_ty)) return true;
    }
    return false;
}

/// Byte offset of direct element `index` inside a packed Tuple (not flattened).
pub fn tuple_element_pack_offset(tuple_ty: []const u8, index: usize) ?usize {
    if (!is_tuple_type_name(tuple_ty)) return null;
    const arity = tuple_arity(tuple_ty) orelse return null;
    if (index >= arity) return null;
    var offset: usize = 0;
    var idx: usize = 0;
    while (idx < index) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return null;
        if (is_tuple_type_name(elem_ty)) {
            offset += tuple_scalar_leaf_storage_byte_width(elem_ty) orelse return null;
        } else if (is_tuple_packable_leaf_type(elem_ty)) {
            offset += type_payload_bytes(elem_ty);
        } else {
            return null;
        }
    }
    return offset;
}

test "tuple type name helpers" {
    try std.testing.expect(is_tuple_type_name("Tuple<i32,bool>"));
    try std.testing.expect(!is_tuple_type_name("Pair<i32,bool>"));
    try std.testing.expectEqual(@as(?usize, 2), tuple_arity("Tuple<i32,bool>"));
    try std.testing.expectEqualStrings("i32", tuple_element_type_at("Tuple<i32,bool>", 0).?);
    try std.testing.expectEqualStrings("bool", tuple_element_type_at("Tuple<i32,bool>", 1).?);
    try std.testing.expectEqualStrings("Tuple", type_base_name("Tuple<i32,bool>"));

    var leaves = std.ArrayList([]const u8).empty;
    defer leaves.deinit(std.testing.allocator);
    try append_tuple_leaf_types(std.testing.allocator, "Tuple<Tuple<i32,u8>,bool>", &leaves);
    try std.testing.expectEqual(@as(usize, 3), leaves.items.len);
    try std.testing.expectEqualStrings("i32", leaves.items[0]);
    try std.testing.expectEqualStrings("u8", leaves.items[1]);
    try std.testing.expectEqualStrings("bool", leaves.items[2]);
}

test "scalar and storage type helpers" {
    try std.testing.expect(is_integer_type_name("i32"));
    try std.testing.expect(is_float_type_name("f64"));
    try std.testing.expect(is_core_wasm_scalar("bool"));
    try std.testing.expect(!is_core_wasm_scalar("text"));
    try std.testing.expect(is_managed_payload_type("text"));
    try std.testing.expect(is_managed_payload_type("[u8]"));
    try std.testing.expect(!is_managed_payload_type("i32"));
    try std.testing.expectEqual(@as(usize, 4), type_payload_bytes("i32"));
    try std.testing.expectEqual(@as(usize, 1), type_payload_bytes("u8"));
    try std.testing.expectEqual(@as(?usize, 4), storage_element_byte_width("i32"));
    try std.testing.expectEqualStrings("[u8]", storage_type_name_for_elem("u8").?);
    try std.testing.expectEqual(@as(?usize, 5), tuple_scalar_leaf_storage_byte_width("Tuple<i32,u8>"));
    try std.testing.expectEqual(@as(?usize, 5), tuple_scalar_leaf_storage_byte_width("Tuple<text,u8>"));
    try std.testing.expect(tuple_has_managed_pack_leaf("Tuple<text,u8>"));
    try std.testing.expect(!tuple_has_managed_pack_leaf("Tuple<i32,u8>"));
    try std.testing.expectEqual(@as(?usize, 0), tuple_element_pack_offset("Tuple<i32,u8>", 0));
    try std.testing.expectEqual(@as(?usize, 4), tuple_element_pack_offset("Tuple<i32,u8>", 1));
    try std.testing.expectEqual(@as(?usize, 6), tuple_scalar_leaf_storage_byte_width("Tuple<Tuple<i32,u8>,u8>"));
}

test "tuple packable leaf and non-packable storage width table" {
    // Terminal pack leaves: core scalars + managed payload handles.
    try std.testing.expect(is_tuple_packable_leaf_type("i32"));
    try std.testing.expect(is_tuple_packable_leaf_type("u8"));
    try std.testing.expect(is_tuple_packable_leaf_type("bool"));
    try std.testing.expect(is_tuple_packable_leaf_type("f64"));
    try std.testing.expect(is_tuple_packable_leaf_type("text"));
    try std.testing.expect(is_tuple_packable_leaf_type("[u8]"));
    // Struct type names are not terminal leaves here; codegen resolves pure-scalar struct slots.
    try std.testing.expect(!is_tuple_packable_leaf_type("Point"));
    try std.testing.expect(!is_tuple_packable_leaf_type("PairBox"));
    // Width without struct table: Point slot → null (codegen supplies struct-aware width).
    try std.testing.expectEqual(@as(?usize, 5), tuple_scalar_leaf_storage_byte_width("Tuple<i32,u8>"));
    try std.testing.expectEqual(@as(?usize, 5), tuple_scalar_leaf_storage_byte_width("Tuple<text,u8>"));
    try std.testing.expectEqual(@as(?usize, 8), tuple_scalar_leaf_storage_byte_width("Tuple<text,[u8]>"));
    try std.testing.expect(tuple_scalar_leaf_storage_byte_width("Tuple<Point,u8>") == null);
    try std.testing.expect(tuple_scalar_leaf_storage_byte_width("Tuple<i32,Point>") == null);
    // Offsets sum preceding packable widths; a non-packable *preceding* leaf nulls later offsets.
    try std.testing.expectEqual(@as(?usize, 0), tuple_element_pack_offset("Tuple<Point,u8>", 0));
    try std.testing.expect(tuple_element_pack_offset("Tuple<Point,u8>", 1) == null);
    try std.testing.expectEqual(@as(?usize, 4), tuple_element_pack_offset("Tuple<i32,Point>", 1));
    try std.testing.expectEqual(@as(?usize, 0), tuple_element_pack_offset("Tuple<text,u8>", 0));
    try std.testing.expectEqual(@as(?usize, 4), tuple_element_pack_offset("Tuple<text,u8>", 1));
}
