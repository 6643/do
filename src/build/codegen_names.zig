const std = @import("std");
const type_util = @import("type_name.zig");

pub fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

pub fn public_decl_name(name: []const u8) []const u8 {
    if (name.len > 1 and name[0] == '.') return name[1..];
    return name;
}

pub fn has_string(items: []const []const u8, target: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, target)) return true;
    }
    return false;
}

pub fn module_scoped_symbol_name(
    allocator: std.mem.Allocator,
    module_idx: usize,
    name: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try append_fmt(allocator, &out, "__mod_{d}__", .{module_idx});
    try append_mangled_type_name(allocator, &out, public_decl_name(name));
    return out.toOwnedSlice(allocator);
}

pub fn append_mangled_type_name(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    for (ty) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9')) {
            try out.append(allocator, ch);
        } else {
            try out.append(allocator, '_');
        }
    }
}

pub fn is_public_type_name(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
}

pub fn is_error_type_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "Error") or std.mem.endsWith(u8, name, "Error");
}

pub fn is_base_int_type_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "i8") or
        std.mem.eql(u8, name, "i16") or
        std.mem.eql(u8, name, "i32") or
        std.mem.eql(u8, name, "i64") or
        std.mem.eql(u8, name, "u8") or
        std.mem.eql(u8, name, "u16") or
        std.mem.eql(u8, name, "u32") or
        std.mem.eql(u8, name, "u64") or
        std.mem.eql(u8, name, "isize") or
        std.mem.eql(u8, name, "usize");
}

pub fn is_numeric_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "add") or
        std.mem.eql(u8, name, "sub") or
        std.mem.eql(u8, name, "mul") or
        std.mem.eql(u8, name, "div") or
        std.mem.eql(u8, name, "rem");
}

pub fn is_bitwise_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "xor") or
        std.mem.eql(u8, name, "shl") or
        std.mem.eql(u8, name, "shr") or
        std.mem.eql(u8, name, "rotl") or
        std.mem.eql(u8, name, "rotr");
}

pub fn is_count_bits_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "clz") or
        std.mem.eql(u8, name, "ctz") or
        std.mem.eql(u8, name, "popcnt");
}

pub fn is_numeric_unary_select_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "abs");
}

pub fn is_numeric_binary_select_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "min") or
        std.mem.eql(u8, name, "max");
}

pub fn is_float_unary_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "neg") or
        std.mem.eql(u8, name, "sqrt") or
        std.mem.eql(u8, name, "ceil") or
        std.mem.eql(u8, name, "floor") or
        std.mem.eql(u8, name, "trunc") or
        std.mem.eql(u8, name, "nearest");
}

pub fn is_float_binary_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "copysign");
}

pub fn is_bool_special_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "not");
}

pub fn is_comparison_core_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "eq") or
        std.mem.eql(u8, name, "ne") or
        std.mem.eql(u8, name, "lt") or
        std.mem.eql(u8, name, "le") or
        std.mem.eql(u8, name, "gt") or
        std.mem.eql(u8, name, "ge");
}

pub fn is_memory_load_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "load_u8") or
        std.mem.eql(u8, name, "load_i8") or
        std.mem.eql(u8, name, "load_u16_le") or
        std.mem.eql(u8, name, "load_i16_le") or
        std.mem.eql(u8, name, "load_u32_le") or
        std.mem.eql(u8, name, "load_i32_le") or
        std.mem.eql(u8, name, "load_u64_le") or
        std.mem.eql(u8, name, "load_i64_le");
}

pub fn is_core_wasm_call_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "is") or
        std.mem.eql(u8, name, "as") or
        is_bool_special_func_name(name) or
        is_numeric_core_func_name(name) or
        is_numeric_unary_select_core_func_name(name) or
        is_numeric_binary_select_core_func_name(name) or
        is_comparison_core_func_name(name) or
        std.mem.eql(u8, name, "get") or
        std.mem.eql(u8, name, "set") or
        std.mem.eql(u8, name, "field_name") or
        std.mem.eql(u8, name, "field_index") or
        std.mem.eql(u8, name, "field_has_default") or
        std.mem.eql(u8, name, "field_get") or
        std.mem.eql(u8, name, "field_set") or
        std.mem.eql(u8, name, "len") or
        std.mem.eql(u8, name, "put") or
        is_memory_load_name(name) or
        is_bitwise_core_func_name(name) or
        is_count_bits_core_func_name(name) or
        is_float_unary_core_func_name(name) or
        is_float_binary_core_func_name(name);
}

pub fn is_core_wasm_scalar(ty: []const u8) bool {
    return type_util.isCoreWasmScalar(ty);
}

pub fn is_core_integer_scalar(ty: []const u8) bool {
    return type_util.isCoreIntegerScalar(ty);
}

pub fn is_core_float_scalar(ty: []const u8) bool {
    return type_util.isCoreFloatScalar(ty);
}
