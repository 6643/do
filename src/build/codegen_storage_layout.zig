//! Storage type parsing, element widths, and layout queries.
//!
//! This module performs no WAT emission.

const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const payload_wat = @import("wat_payload.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_imports = @import("codegen_imports.zig");
const find_value_enum_decl_line_by_name = codegen_imports.find_value_enum_decl_line_by_name;
const find_value_enum_decl_line_by_branch = codegen_imports.find_value_enum_decl_line_by_branch;
const simple_type_name = codegen_collect_functions.simple_type_name;
const is_top_level_comma_any = codegen_collect_functions.is_top_level_comma_any;
const is_return_arrow_at = codegen_collect_functions.is_return_arrow_at;
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_host_imports = @import("codegen_host_imports.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const tok_eq = codegen_tokens.tok_eq;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const align_up = codegen_tokens.align_up;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const public_decl_name = codegen_names.public_decl_name;
const is_string_literal_arg = codegen_tokens.is_string_literal_arg;
const find_type_arg_end = codegen_tokens.find_type_arg_end;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const is_core_integer_scalar = codegen_names.is_core_integer_scalar;
const is_core_float_scalar = codegen_names.is_core_float_scalar;
const is_numeric_core_func_name = codegen_names.is_numeric_core_func_name;
const is_bitwise_core_func_name = codegen_names.is_bitwise_core_func_name;
const is_count_bits_core_func_name = codegen_names.is_count_bits_core_func_name;
const is_numeric_unary_select_core_func_name = codegen_names.is_numeric_unary_select_core_func_name;
const is_numeric_binary_select_core_func_name = codegen_names.is_numeric_binary_select_core_func_name;
const is_float_unary_core_func_name = codegen_names.is_float_unary_core_func_name;
const is_float_binary_core_func_name = codegen_names.is_float_binary_core_func_name;
const is_bool_special_func_name = codegen_names.is_bool_special_func_name;
const is_comparison_core_func_name = codegen_names.is_comparison_core_func_name;
const is_memory_load_name = codegen_names.is_memory_load_name;
const token_text_equals_compact = codegen_tokens.token_text_equals_compact;
const find_top_level_type_separator = codegen_tokens.find_top_level_type_separator;
const find_top_level_type_separator_from = codegen_tokens.find_top_level_type_separator_from;
const LocalSet = context.LocalSet;
const Local = model.Local;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const StructDecl = model.StructDecl;
const StructField = model.StructField;
const StructLayout = model.StructLayout;
const StorageLocal = model.StorageLocal;
const UnionLocal = model.UnionLocal;
const FuncDecl = model.FuncDecl;
const FuncParam = model.FuncParam;
const FieldMetaLocal = model.FieldMetaLocal;
const GenericTypeBinding = model.GenericTypeBinding;
const ValueEnumDecl = model.ValueEnumDecl;
const CallbackBinding = model.CallbackBinding;
const CallbackCallArg = model.CallbackCallArg;
const FuncTypeShape = model.FuncTypeShape;
const LambdaExprShape = model.LambdaExprShape;
const NarrowedUnionLocal = model.NarrowedUnionLocal;
const UnionStructPayload = model.UnionStructPayload;
const ExprCallHead = model.ExprCallHead;
const find_local_type = context.find_local_type;
const find_storage_local = context.find_storage_local;
const find_struct_local = context.find_struct_local;
const find_union_local = context.find_union_local;
const storage_type_name_for_elem = context.storage_type_name_for_elem;
const local_name_matches = context.local_name_matches;
const free_union_layout = codegen_union_layout.free_union_layout;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const find_struct_layout_exact = codegen_collect_structs.find_struct_layout_exact;
const is_pack_managed_handle_leaf = codegen_collect_structs.is_pack_managed_handle_leaf;
const pure_scalar_struct_pack_width = codegen_collect_util.pure_scalar_struct_pack_width;
const tuple_pack_width_with_structs = codegen_collect_util.tuple_pack_width_with_structs;
const is_error_like_type = codegen_collect_util.is_error_like_type;
const parse_type_union_layout_from_name = codegen_collect_structs.parse_type_union_layout_from_name;
const bind_struct_type_args = codegen_collect_structs.bind_struct_type_args;
const substitute_generic_type_owned = codegen_collect_util.substitute_generic_type_owned;
const find_generic_binding = codegen_collect_util.find_generic_binding;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const expr_call_head = codegen_imports.expr_call_head;
const call_head_has_type_args = codegen_imports.call_head_has_type_args;
const find_value_enum_decl = codegen_imports.find_value_enum_decl;
const find_codegen_import_by_alias = codegen_imports.find_codegen_import_by_alias;
const imported_alias_context_for_tokens = codegen_imports.imported_alias_context_for_tokens;
const local_scalar_const = codegen_imports.local_scalar_const;
const imported_scalar_const = codegen_imports.imported_scalar_const;
const find_imported_module_index_no_alloc = codegen_imports.find_imported_module_index_no_alloc;
const find_wasi_host_import_for_tokens = codegen_imports.find_wasi_host_import_for_tokens;
const find_host_import_for_tokens = codegen_host_imports.find_host_import_for_tokens;
const find_local_name = context.find_local_name;
const is_union_payload_local_name = context.is_union_payload_local_name;
const union_payload_local_name_from_locals = context.union_payload_local_name_from_locals;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;

pub const TupleElementInfo = struct {
    index: usize,
    ty: []const u8,
};

pub const ParsedStorageType = struct {
    elem_ty: []const u8,
    next_idx: usize,
};

pub const ManagedPayloadBinding = struct {
    ty: []const u8,
    elem_ty: []const u8,
};

pub fn is_managed_local_type(ty: []const u8, ctx: CodegenContext) bool {
    if (is_managed_payload_type(ty)) return true;
    if (find_struct_layout_exact(ctx.struct_layouts, ty)) |layout| {
        if (layout.is_storage_pack) return false;
    }
    return find_struct_layout(ctx.struct_layouts, ty) != null;
}

pub fn codegen_types_compatible(expected: []const u8, actual: []const u8) bool {
    if (std.mem.eql(u8, expected, actual)) return true;
    if (std.mem.eql(u8, expected, "text") and std.mem.eql(u8, actual, "[u8]")) return true;
    if (std.mem.eql(u8, expected, "[u8]") and std.mem.eql(u8, actual, "text")) return true;
    return false;
}

pub fn type_payload_bytes(ty: []const u8) usize {
    return type_util.type_payload_bytes(ty);
}

pub fn type_payload_alignment(ty: []const u8) usize {
    return type_util.type_payload_alignment(ty);
}

pub fn is_managed_payload_type(ty: []const u8) bool {
    return type_util.is_managed_payload_type(ty);
}

pub fn is_storage_type_name(ty: []const u8) bool {
    return type_util.is_storage_type_name(ty);
}

pub fn storage_elem_type_from_name(ty: []const u8) ?[]const u8 {
    return type_util.storage_elem_type_from_name(ty);
}

pub fn storage_element_byte_width(elem_ty: []const u8) ?usize {
    return type_util.storage_element_byte_width(elem_ty);
}

pub fn is_tuple_type_name(ty: []const u8) bool {
    return type_util.is_tuple_type_name(ty);
}

pub fn tuple_arity(tuple_ty: []const u8) ?usize {
    return type_util.tuple_arity(tuple_ty);
}

pub fn tuple_element_type_at(tuple_ty: []const u8, idx: usize) ?[]const u8 {
    return type_util.tuple_element_type_at(tuple_ty, idx);
}

pub fn tuple_get_element_info(tokens: []const lexer.Token, second_start: usize, second_end: usize, tuple_ty: []const u8) ?TupleElementInfo {
    if (second_end != second_start + 1) return null;
    if (tokens[second_start].kind != .number) return null;
    const index = std.fmt.parseInt(usize, tokens[second_start].lexeme, 10) catch return null;
    const ty = tuple_element_type_at(tuple_ty, index) orelse return null;
    return .{ .index = index, .ty = ty };
}

pub fn find_storage_primitive_local(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    const local = find_storage_local(locals, name) orelse return null;
    if (storage_elem_type_from_name(local.ty) == null) return null;
    return local;
}

pub fn struct_field_payload_offset(decl: StructDecl, field_name: []const u8) ?usize {
    var offset: usize = 0;
    for (decl.fields) |field| {
        offset = align_up(offset, type_payload_alignment(field.ty));
        if (std.mem.eql(u8, public_decl_name(field.name), field_name)) return offset;
        offset += type_payload_bytes(field.ty);
    }
    return null;
}

pub fn wasm_type(ty: []const u8) []const u8 {
    return payload_wat.wasm_type(ty);
}

pub fn codegen_scalar_type(ctx: CodegenContext, ty: []const u8) []const u8 {
    return value_enum_carrier(ctx, ty) orelse ty;
}

pub fn codegen_wasm_type(ctx: CodegenContext, ty: []const u8) []const u8 {
    return wasm_type(codegen_scalar_type(ctx, ty));
}

pub fn tuple_scalar_leaf_storage_byte_width(tuple_ty: []const u8) ?usize {
    return type_util.tuple_scalar_leaf_storage_byte_width(tuple_ty);
}

pub fn tuple_scalar_leaf_storage_byte_width_ctx(tuple_ty: []const u8, ctx: CodegenContext) ?usize {
    if (tuple_pack_width_with_structs(tuple_ty, ctx.structs)) |w| return w;
    return tuple_scalar_leaf_storage_byte_width(tuple_ty);
}

pub fn tuple_has_managed_pack_leaf(tuple_ty: []const u8) bool {
    return type_util.tuple_has_managed_pack_leaf(tuple_ty);
}

pub fn tuple_has_managed_pack_leaf_with_structs(tuple_ty: []const u8, structs: []const StructDecl) bool {
    if (!is_tuple_type_name(tuple_ty)) return false;
    const arity = tuple_arity(tuple_ty) orelse return false;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return false;
        if (is_tuple_type_name(elem_ty)) {
            if (tuple_has_managed_pack_leaf_with_structs(elem_ty, structs)) return true;
            continue;
        }
        if (is_pack_managed_handle_leaf(elem_ty, structs)) return true;
    }
    return false;
}

pub fn tuple_has_managed_pack_leaf_ctx(tuple_ty: []const u8, ctx: CodegenContext) bool {
    if (tuple_has_managed_pack_leaf_with_structs(tuple_ty, ctx.structs)) return true;
    return tuple_has_managed_pack_leaf(tuple_ty);
}

pub fn storage_type_id_for_element(elem_ty: []const u8, ctx: CodegenContext) usize {
    if (is_tuple_type_name(elem_ty) and tuple_has_managed_pack_leaf_ctx(elem_ty, ctx)) {
        if (find_struct_layout_exact(ctx.struct_layouts, elem_ty)) |layout| {
            if (layout.is_storage_pack) return layout.type_id;
        }
    }
    if (is_managed_local_type(elem_ty, ctx) and storage_element_byte_width(elem_ty) == null and tuple_scalar_leaf_storage_byte_width_ctx(elem_ty, ctx) == null)
        return constants.TYPE_ID_STORAGE_MANAGED;
    return constants.TYPE_ID_STORAGE_U8;
}

fn branch_value_in_wasi_enum_arms(
    tokens: []const lexer.Token,
    arms_start: usize,
    close_call: usize,
    branch_name: []const u8,
) ?usize {
    var arm_idx = arms_start;
    while (arm_idx < close_call) : (arm_idx += 1) {
        if (tok_eq(tokens[arm_idx], ",")) {
            arm_idx += 1;
            break;
        }
    }
    var branch_idx: usize = 1;
    while (arm_idx < close_call) : (arm_idx += 1) {
        if (tok_eq(tokens[arm_idx], "|") or tok_eq(tokens[arm_idx], ",")) continue;
        if (tokens[arm_idx].kind != .ident) return null;
        const arm = tokens[arm_idx].lexeme;
        const has_discr = arm_idx + 3 < close_call and tok_eq(tokens[arm_idx + 1], "(") and
            tokens[arm_idx + 2].kind == .number and tok_eq(tokens[arm_idx + 3], ")");
        if (std.mem.eql(u8, arm, branch_name)) return branch_idx;
        if (has_discr) arm_idx += 3;
        branch_idx += 1;
    }
    return null;
}

fn branch_value_in_plain_error_arms(
    tokens: []const lexer.Token,
    arms_start: usize,
    line_end: usize,
    branch_name: []const u8,
) ?usize {
    var idx = arms_start;
    var branch_idx: usize = 1;
    while (idx < line_end) : (idx += 1) {
        if (tok_eq(tokens[idx], "|")) continue;
        if (tokens[idx].kind != .ident) return null;
        if (std.mem.eql(u8, tokens[idx].lexeme, branch_name)) return branch_idx;
        branch_idx += 1;
    }
    return null;
}

pub fn error_enum_branch_value(tokens: []const lexer.Token, enum_name: []const u8, branch_name: []const u8) ?usize {
    var brace_depth: usize = 0;
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            brace_depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (brace_depth > 0) brace_depth -= 1;
            continue;
        }
        if (brace_depth != 0) continue;
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, enum_name)) continue;
        if (!tok_eq(tokens[idx + 1], "error") or !tok_eq(tokens[idx + 2], "=")) continue;

        const line_end = find_line_end(tokens, idx);
        const arms_start = idx + 3;
        if (arms_start < line_end and tok_eq(tokens[arms_start], "@") and arms_start + 2 < line_end and
            tokens[arms_start + 1].kind == .ident and std.mem.eql(u8, tokens[arms_start + 1].lexeme, "wasi_enum") and
            tok_eq(tokens[arms_start + 2], "("))
        {
            const close_call = find_matching_in_range(tokens, arms_start + 2, "(", ")", line_end) catch return null;
            return branch_value_in_wasi_enum_arms(tokens, arms_start + 3, close_call, branch_name);
        }
        return branch_value_in_plain_error_arms(tokens, arms_start, line_end, branch_name);
    }
    return null;
}

pub fn direct_managed_local_expr_name(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (end_idx != start_idx + 1) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const name = tokens[start_idx].lexeme;

    if (find_union_local(locals.union_locals.items, name)) |union_local| {
        const payload_ty = union_local_default_payload_type(tokens, union_local) orelse return null;
        if (!is_managed_local_type(payload_ty, ctx)) return null;
        var matched_idx: ?usize = null;
        for (union_local.layout.payload_tys, 0..) |candidate_ty, idx| {
            if (!std.mem.eql(u8, candidate_ty, payload_ty)) continue;
            if (matched_idx != null) return null;
            matched_idx = idx;
        }
        return union_payload_local_name_from_locals(locals.locals.items, union_local.name, matched_idx orelse return null);
    }

    const ty = find_local_type(locals.locals.items, name) orelse return null;
    if (!is_managed_local_type(ty, ctx)) return null;
    if (is_union_payload_local_name(locals.union_locals.items, name)) return name;
    return find_local_name(locals.locals.items, name);
}

pub fn is_direct_managed_local_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    return direct_managed_local_expr_name(tokens, start_idx, end_idx, locals, ctx) != null;
}

pub fn value_enum_carrier(ctx: CodegenContext, ty: []const u8) ?[]const u8 {
    const decl = find_value_enum_decl(ctx.value_enums, ty) orelse return null;
    return decl.carrier;
}

pub fn is_codegen_scalar_type(ctx: CodegenContext, ty: []const u8) bool {
    return codegen_names.is_core_wasm_scalar(ty) or value_enum_carrier(ctx, ty) != null;
}

pub fn find_union_branch_by_type(layout: codegen_union_layout.UnionLayout, ty: []const u8) ?codegen_union_layout.UnionBranch {
    for (layout.branches) |branch| {
        if (codegen_types_compatible(branch.ty, ty)) return branch;
    }
    return null;
}

pub fn union_payload_comparison_branch_for_value(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: codegen_union_layout.UnionLayout,
) ?codegen_union_layout.UnionBranch {
    if (layout.payload_tys.len != 1) return null;
    for (layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1 or branch.payload_start != 0) continue;
        if (!is_codegen_scalar_type(ctx, branch.ty)) continue;
        if (!call_arg_matches_param(tokens, value_start, value_end, locals, ctx, branch.ty)) continue;
        return branch;
    }
    return null;
}

pub fn union_payload_comparison_call_branch(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?codegen_union_layout.UnionBranch {
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tok_eq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, args_end);
    if (second_end != args_end) return null;
    const range = trim_parens(tokens, args_start, first_end);
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return null;
    const layout = func.result_union orelse return null;
    return union_payload_comparison_branch_for_value(tokens, second_start, second_end, locals, ctx, layout);
}

pub fn is_storage_agg_literal_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tok_eq(tokens[start_idx], ".")) return false;
    if (!tok_eq(tokens[start_idx + 1], "{")) return false;
    const close_brace = find_matching_in_range(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    return close_brace + 1 == end_idx;
}

pub fn infer_storage_content_comparison_type(
    tokens: []const lexer.Token,
    left_start: usize,
    left_end: usize,
    right_start: usize,
    right_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const left_ty = infer_expr_type(tokens, left_start, left_end, locals, ctx);
    const right_ty = infer_expr_type(tokens, right_start, right_end, locals, ctx);
    if (left_ty) |ty| {
        if (is_managed_payload_comparable_type(ty) and storage_content_arg_compatible(tokens, right_start, right_end, right_ty, ty)) return ty;
    }
    if (right_ty) |ty| {
        if (is_managed_payload_comparable_type(ty) and storage_content_arg_compatible(tokens, left_start, left_end, left_ty, ty)) return ty;
    }
    if (is_string_literal_arg(tokens, left_start, left_end) and is_string_literal_arg(tokens, right_start, right_end)) return "text";
    return null;
}

pub fn storage_content_arg_compatible(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, inferred_ty: ?[]const u8, target_ty: []const u8) bool {
    if (inferred_ty) |ty| return codegen_types_compatible(target_ty, ty);
    if (is_storage_agg_literal_expr(tokens, start_idx, end_idx)) return true;
    return is_string_literal_arg(tokens, start_idx, end_idx);
}

pub fn is_managed_payload_comparable_type(ty: []const u8) bool {
    return managed_payload_elem_type_from_name(ty) != null;
}

pub fn storage_binding_elem_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 5 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const parsed = parse_storage_type(tokens, start_idx + 1, end_idx) orelse return null;
    if (find_top_level_token(tokens, parsed.next_idx, end_idx, "=") == null) return null;
    return parsed.elem_ty;
}

pub fn managed_payload_binding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ManagedPayloadBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    const ty = tokens[start_idx + 1].lexeme;
    if (storage_elem_type_from_name(ty) != null) return null;
    const elem_ty = managed_payload_elem_type_from_name(ty) orelse return null;
    if (find_top_level_token(tokens, start_idx + 2, end_idx, "=") == null) return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

pub fn parse_storage_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ParsedStorageType {
    if (start_idx + 2 >= end_idx) return null;
    if (!tok_eq(tokens[start_idx], "[")) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    if (!tok_eq(tokens[start_idx + 2], "]")) return null;
    return .{
        .elem_ty = tokens[start_idx + 1].lexeme,
        .next_idx = start_idx + 3,
    };
}

pub fn storage_element_byte_width_for_type(elem_ty: []const u8, ctx: CodegenContext) ?usize {
    if (storage_element_byte_width(elem_ty)) |width| return width;
    if (tuple_scalar_leaf_storage_byte_width_ctx(elem_ty, ctx)) |width| return width;
    if (is_managed_local_type(elem_ty, ctx)) return 4;
    return null;
}

pub fn storage_pack_layout_for_elem(elem_ty: []const u8, ctx: CodegenContext) ?StructLayout {
    if (!is_tuple_type_name(elem_ty) or !tuple_has_managed_pack_leaf_ctx(elem_ty, ctx)) return null;
    const layout = find_struct_layout_exact(ctx.struct_layouts, elem_ty) orelse return null;
    if (!layout.is_storage_pack) return null;
    return layout;
}

pub fn tuple_field_path_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident or first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or !is_dot_ident(tokens[field_start].lexeme) or field_end >= end_idx or !tok_eq(tokens[field_end], ",")) return null;
    const index_start = field_end + 1;
    const index_end = find_arg_end(tokens, index_start, end_idx);
    if (index_end != end_idx) return null;

    const struct_local = find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null;
    const decl = find_struct_decl(ctx.structs, struct_local.ty) orelse return null;
    const field_ty = find_local_field_type(locals.locals.items, struct_local.name, public_decl_name(tokens[field_start].lexeme)) orelse
        find_struct_field_type(decl, public_decl_name(tokens[field_start].lexeme)) orelse return null;
    if (!is_tuple_type_name(field_ty)) return null;
    return field_ty;
}

pub fn substitute_struct_field_type(allocator: std.mem.Allocator, decl: StructDecl, concrete_ty: []const u8, field_ty: []const u8, owned_types: *std.ArrayList([]const u8)) ![]const u8 {
    if (decl.type_params.len == 0) return field_ty;
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    if (!try bind_struct_type_args(allocator, decl, concrete_ty, &bindings, owned_types)) return field_ty;
    return try substitute_generic_type_owned(allocator, field_ty, bindings.items, owned_types);
}

pub fn find_local_field_type(locals: []const Local, base: []const u8, field: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_field_name_matches(local.name, base, field)) return local.ty;
        if (local.source_name) |source| {
            if (local_field_name_matches(source, base, field)) return local.ty;
        }
    }
    return null;
}

pub fn find_func_decl_for_call_head(
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?FuncDecl {
    const name = tokens[call_head.name_idx].lexeme;
    if (!call_head_has_type_args(call_head)) {
        return find_func_decl_for_call(tokens, call_head.args_start, call_head.args_end, locals, ctx, name);
    }

    var fallback: ?FuncDecl = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, tokens)) continue;
        if (!same_callable_source_name(func.source_name, name)) continue;
        if (!call_explicit_type_args_match_bindings(tokens, call_head, func.type_bindings)) continue;
        if (!call_args_match_func_params(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;

    const import_ref = find_codegen_import_by_alias(tokens, name) orelse return null;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!std.mem.eql(u8, func.name, import_ref.alias)) continue;
        if (!call_explicit_type_args_match_bindings(tokens, call_head, func.type_bindings)) continue;
        if (!call_args_match_func_params(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;

    const import_ctx = imported_alias_context_for_tokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = find_imported_module_index_no_alloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, child_tokens)) continue;
        if (!same_callable_source_name(func.source_name, import_ref.alias)) continue;
        if (!call_explicit_type_args_match_bindings(tokens, call_head, func.type_bindings)) continue;
        if (!call_args_match_func_params(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, child_tokens)) continue;
        if (!same_callable_source_name(func.source_name, public_decl_name(import_ref.target))) continue;
        if (!call_explicit_type_args_match_bindings(tokens, call_head, func.type_bindings)) continue;
        if (!call_args_match_func_params(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    return fallback;
}

pub fn infer_expr_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .ident) {
            if (find_narrowed_union_type(locals.narrowed_union_locals.items, tok.lexeme)) |ty| return substitute_generic_type(ty, ctx.type_bindings);
            if (find_local_type(locals.locals.items, tok.lexeme)) |ty| return ty;
            if (find_struct_local(locals.struct_locals.items, tok.lexeme)) |struct_local| return struct_local.ty;
            if (find_union_local(locals.union_locals.items, tok.lexeme)) |union_local| {
                return substitute_generic_type(union_local.layout.source_ty, ctx.type_bindings);
            }
            if (find_callback_call_arg(ctx.callback_call_args, tok.lexeme)) |callback_arg| return callback_arg.ty;
            return if (local_scalar_const(tokens, tok.lexeme)) |local_const| local_const.ty else if (imported_scalar_const(ctx, tokens, tok.lexeme)) |imported_const| imported_const.ty else null;
        }
        return null;
    }

    const call_head = expr_call_head(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic) {
        if (should_infer_bool_special_call(call_name, tokens, call_head.args_start, call_head.args_end, locals, ctx)) return "bool";
        if (std.mem.eql(u8, call_name, "is")) return "bool";
        if (std.mem.eql(u8, call_name, "as")) return infer_scalar_as_call_type(tokens, call_head.args_start, call_head.args_end);
        if (is_comparison_core_func_name(call_name)) return "bool";
        if (std.mem.eql(u8, call_name, "len")) return "usize";
        if (std.mem.eql(u8, call_name, "set")) return infer_set_call_type(tokens, call_head.args_start, call_head.args_end, locals);
        if (std.mem.eql(u8, call_name, "put")) return infer_put_call_type(tokens, call_head.args_start, call_head.args_end, locals);
        if (std.mem.eql(u8, call_name, "field_name")) return "text";
        if (std.mem.eql(u8, call_name, "field_index")) return "usize";
        if (std.mem.eql(u8, call_name, "field_has_default")) return "bool";
        if (std.mem.eql(u8, call_name, "field_get")) {
            return infer_field_get_call_type(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (std.mem.eql(u8, call_name, "field_set")) {
            return infer_field_set_call_type(tokens, call_head.args_start, call_head.args_end, locals);
        }
        if (std.mem.eql(u8, call_name, "get")) {
            return infer_get_call_type(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (is_memory_load_name(call_name)) return memory_load_result_type(call_name);
        if (is_numeric_core_func_name(call_name)) {
            return infer_first_arg_type_or_default_s32(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (is_bitwise_core_func_name(call_name)) {
            return infer_expr_type(tokens, call_head.args_start, find_arg_end(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (is_count_bits_core_func_name(call_name)) {
            return infer_expr_type(tokens, call_head.args_start, find_arg_end(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (is_numeric_unary_select_core_func_name(call_name)) {
            const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
            const source_ty = infer_expr_type(tokens, call_head.args_start, first_end, locals, ctx) orelse "i32";
            return abs_result_type(source_ty);
        }
        if (is_numeric_binary_select_core_func_name(call_name)) {
            return infer_expr_type(tokens, call_head.args_start, find_arg_end(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (is_float_unary_core_func_name(call_name) or is_float_binary_core_func_name(call_name)) {
            return infer_expr_type(tokens, call_head.args_start, find_arg_end(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
    }

    if (find_callback_binding(ctx.callback_bindings, call_name)) |binding| return binding.shape.return_type;
    if (find_func_decl_for_call_head(tokens, call_head, locals, ctx)) |func| return func.result;
    if (find_wasi_host_import_for_tokens(ctx, tokens, call_name)) |import| return wasi_do_result_type(import);
    if (find_host_import_for_tokens(ctx.host_imports, tokens, call_name)) |host_import| return host_import.result;
    return null;
}

pub fn find_struct_field_type(decl: StructDecl, field_name: []const u8) ?[]const u8 {
    for (decl.fields) |field| {
        if (std.mem.eql(u8, public_decl_name(field.name), field_name)) return field.ty;
    }
    return null;
}

pub fn local_field_name_matches(name: []const u8, base: []const u8, field: []const u8) bool {
    if (name.len != base.len + 1 + field.len) return false;
    if (!std.mem.eql(u8, name[0..base.len], base)) return false;
    if (name[base.len] != '.') return false;
    return std.mem.eql(u8, name[base.len + 1 ..], field);
}

pub fn struct_literal_open_rhs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 >= end_idx) return null;
    if (tokens[start_idx].kind == .ident and tok_eq(tokens[start_idx + 1], "{")) return start_idx + 1;
    if (tokens[start_idx].kind == .ident and tok_eq(tokens[start_idx + 1], "<")) {
        const close_angle = find_matching_in_range(tokens, start_idx + 1, "<", ">", end_idx) catch return null;
        if (close_angle + 1 < end_idx and tok_eq(tokens[close_angle + 1], "{")) return close_angle + 1;
    }
    if (tok_eq(tokens[start_idx], ".") and tok_eq(tokens[start_idx + 1], "{")) return start_idx + 1;
    return null;
}

pub fn substitute_generic_type(ty: []const u8, bindings: []const GenericTypeBinding) []const u8 {
    if (find_generic_binding(bindings, ty)) |binding| return binding.ty;
    return ty;
}

pub fn find_callback_call_arg(args: []const CallbackCallArg, name: []const u8) ?CallbackCallArg {
    for (args) |arg| {
        if (std.mem.eql(u8, arg.source_name, name)) return arg;
    }
    return null;
}

pub fn append_tuple_local_fields_borrowed(allocator: std.mem.Allocator, out: *LocalSet, tokens: []const lexer.Token, ctx: CodegenContext, base: []const u8, tuple_ty: []const u8) CodegenError!void {
    const arity = tuple_arity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return error.UnsupportedLowering;
        var field_buf: [32]u8 = undefined;
        const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{idx});
        try append_borrowed_local_field(allocator, out, tokens, ctx, base, field_name, elem_ty);
    }
}

pub fn find_func_decl_for_call(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    name: []const u8,
) ?FuncDecl {
    var fallback: ?FuncDecl = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, tokens)) continue;
        if (!same_callable_source_name(func.source_name, name)) continue;
        if (!call_args_match_func_params(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    const import_ref = find_codegen_import_by_alias(tokens, name) orelse return null;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!std.mem.eql(u8, func.name, import_ref.alias)) continue;
        if (!call_args_match_func_params(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    const import_ctx = imported_alias_context_for_tokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = find_imported_module_index_no_alloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, child_tokens)) continue;
        if (!same_callable_source_name(func.source_name, import_ref.alias)) continue;
        if (!call_args_match_func_params(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, child_tokens)) continue;
        if (!same_callable_source_name(func.source_name, public_decl_name(import_ref.target))) continue;
        if (!call_args_match_func_params(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    return fallback;
}

pub fn call_explicit_type_args_match_bindings(tokens: []const lexer.Token, call_head: ExprCallHead, bindings: []const GenericTypeBinding) bool {
    if (bindings.len == 0) return false;

    var type_start = call_head.type_args_start;
    var binding_idx: usize = 0;
    while (type_start < call_head.type_args_end) {
        if (binding_idx >= bindings.len) return false;
        if (tok_eq(tokens[type_start], ",")) return false;

        const type_end = find_type_arg_end(tokens, type_start, call_head.type_args_end);
        if (type_end == type_start) return false;
        if (!token_text_equals_compact(tokens, type_start, type_end, bindings[binding_idx].ty)) return false;

        binding_idx += 1;
        type_start = type_end;
        if (type_start < call_head.type_args_end) {
            if (!tok_eq(tokens[type_start], ",")) return false;
            type_start += 1;
            if (type_start >= call_head.type_args_end) return false;
        }
    }
    return binding_idx == bindings.len;
}

pub fn call_args_match_func_params(tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, func: FuncDecl) bool {
    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end and (param_idx < func.params.len and !func.params[param_idx].variadic)) {
        const arg_end = find_arg_end(tokens, arg_start, args_end);
        if (func.params[param_idx].callback) |callback| {
            if (!call_arg_matches_callback_shape(tokens, arg_start, arg_end, locals, ctx, callback.shape)) return false;
            if (find_callback_binding(func.callback_bindings, func.params[param_idx].name)) |binding| {
                if (!call_arg_matches_concrete_callback_binding(tokens, arg_start, arg_end, ctx, callback.shape, binding)) return false;
            }
        } else if (!call_arg_matches_param(tokens, arg_start, arg_end, locals, ctx, func.params[param_idx].ty)) {
            return false;
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx == func.params.len) return arg_start >= args_end;
    if (!func.params[param_idx].variadic) return false;
    if (param_idx + 1 != func.params.len) return false;
    return call_args_match_variadic_tail(tokens, arg_start, args_end, locals, ctx, func_variadic_elem_type(func.params[param_idx]));
}

pub fn append_borrowed_local_field(allocator: std.mem.Allocator, out: *LocalSet, tokens: []const lexer.Token, ctx: CodegenContext, base: []const u8, field: []const u8, ty: []const u8) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, public_decl_name(field) });
    if (is_tuple_type_name(ty)) {
        try out.owned_names.append(allocator, name);
        const local_name = try out.append_struct_local(allocator, name, ty, false);
        try append_tuple_local_fields_borrowed(allocator, out, tokens, ctx, local_name, ty);
        return;
    }
    if (find_struct_decl(ctx.structs, ty)) |decl| {
        if (find_struct_layout(ctx.struct_layouts, ty) == null and pure_scalar_struct_pack_width(decl, ctx.structs) != null) {
            try out.owned_names.append(allocator, name);
            const local_name = try out.append_struct_local(allocator, name, ty, false);
            for (decl.fields) |sf| {
                const field_ty = try substitute_struct_field_type(allocator, decl, ty, sf.ty, &out.owned_names);
                try append_borrowed_local_field(allocator, out, tokens, ctx, local_name, sf.name, field_ty);
            }
            return;
        }
    }
    try out.owned_names.append(allocator, name);
    if (try parse_type_union_layout_from_name(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, &out.owned_names)) |layout| {
        errdefer free_union_layout(allocator, layout);
        return out.append_union_local(allocator, name, layout, false, true);
    }
    try out.append_borrowed_local(allocator, name, ty, false);
}

pub fn should_infer_bool_special_call(name: []const u8, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    if (!is_bool_special_func_name(name)) return false;
    if (std.mem.eql(u8, name, "not")) return true;
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end == args_start + 1 and (tok_eq(tokens[args_start], "true") or tok_eq(tokens[args_start], "false"))) return true;
    const first_ty = infer_expr_type(tokens, args_start, first_end, locals, ctx) orelse return false;
    return std.mem.eql(u8, first_ty, "bool");
}

pub fn call_arg_matches_callback_shape(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    shape: FuncTypeShape,
) bool {
    if (lambda_expr_shape(tokens, arg_start, arg_end)) |lambda| {
        return call_arg_matches_callback_lambda(tokens, lambda, locals, ctx, shape);
    }

    const range = trim_parens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    if (find_callback_binding(ctx.callback_bindings, tokens[range.start].lexeme)) |binding| {
        return callback_bindings_have_same_shape(binding.shape, shape);
    }
    return find_callback_ref_func(tokens, ctx, tokens[range.start].lexeme, shape) != null;
}

fn call_arg_matches_callback_lambda(
    tokens: []const lexer.Token,
    lambda: LambdaExprShape,
    locals: *const LocalSet,
    ctx: CodegenContext,
    shape: FuncTypeShape,
) bool {
    if (lambda_param_count(tokens, lambda.open_params + 1, lambda.close_params) != shape.param_types.len) return false;
    if (!lambda_explicit_types_match_shape(tokens, lambda, shape)) return false;
    if (shape.return_type == null and lambda.is_block and is_return_arrow_at(tokens, lambda.close_params + 1)) {
        if (lambda_explicit_return_type(tokens, lambda)) |lambda_ret| {
            if (!std.mem.eql(u8, lambda_ret, "nil")) return false;
        }
    }
    return callback_lambda_return_matches_shape(tokens, lambda, shape, locals, ctx);
}

pub fn infer_scalar_as_call_type(tokens: []const lexer.Token, args_start: usize, args_end: usize) ?[]const u8 {
    const target_end = find_arg_end(tokens, args_start, args_end);
    if (target_end == args_start or target_end >= args_end or !tok_eq(tokens[target_end], ",")) return null;
    return scalar_as_target_type(tokens, args_start, target_end);
}

pub fn find_callback_binding(bindings: []const CallbackBinding, name: []const u8) ?CallbackBinding {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.param_name, name)) return binding;
    }
    return null;
}

pub fn scalar_as_target_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!is_scalar_as_target_type_name(tokens[start_idx].lexeme)) return null;
    return tokens[start_idx].lexeme;
}

pub fn call_arg_matches_concrete_callback_binding(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, ctx: CodegenContext, shape: FuncTypeShape, binding: CallbackBinding) bool {
    if (!callback_bindings_have_same_shape(binding.shape, shape)) return false;
    if (lambda_expr_shape(tokens, arg_start, arg_end) != null) {
        return binding.kind == .lambda and module_tokens_equal(binding.arg_tokens, tokens) and binding.arg_start == arg_start and binding.arg_end == arg_end;
    }

    const range = trim_parens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    const name = tokens[range.start].lexeme;
    if (find_callback_binding(ctx.callback_bindings, name)) |upstream| {
        return callback_binding_has_same_concrete_arg(binding, upstream);
    }
    if (binding.kind != .func_ref) return false;
    const func_name = binding.func_name orelse return false;
    return module_tokens_equal(binding.arg_tokens, tokens) and same_callable_source_name(func_name, name);
}

pub fn is_scalar_as_target_type_name(name: []const u8) bool {
    const names = [_][]const u8{
        "u8",
        "u16",
        "u32",
        "u64",
        "usize",
        "isize",
        "i8",
        "i16",
        "i32",
        "i64",
        "f32",
        "f64",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

pub fn infer_set_call_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, end_idx);
    if (second_end >= end_idx or !tok_eq(tokens[second_end], ",")) return null;
    if (find_arg_end(tokens, second_end + 1, end_idx) != end_idx) return null;

    if (find_storage_primitive_local(locals.storage_locals.items, tokens[start_idx].lexeme)) |storage| return storage.ty;
    if (find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme)) |struct_local| return struct_local.ty;
    return null;
}

pub fn callback_bindings_have_same_shape(left: FuncTypeShape, right: FuncTypeShape) bool {
    if (left.param_types.len != right.param_types.len) return false;
    for (left.param_types, 0..) |left_ty, idx| {
        const right_ty = right.param_types[idx];
        if (left_ty == null or right_ty == null) continue;
        if (!std.mem.eql(u8, left_ty.?, right_ty.?)) return false;
    }
    if (left.return_type == null and right.return_type == null) return true;
    if (left.return_type == null or right.return_type == null) return false;
    return std.mem.eql(u8, left.return_type.?, right.return_type.?);
}

pub fn call_arg_matches_param(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, locals: *const LocalSet, ctx: CodegenContext, param_ty: []const u8) bool {
    if (find_top_level_type_separator(param_ty, '|') != null) {
        return call_arg_matches_union_param(tokens, arg_start, arg_end, locals, ctx, param_ty);
    }

    if (infer_expr_type(tokens, arg_start, arg_end, locals, ctx)) |arg_ty| {
        return codegen_types_compatible(param_ty, arg_ty);
    }

    if (managed_payload_elem_type_from_name(param_ty) != null and is_storage_agg_literal_expr(tokens, arg_start, arg_end)) {
        return true;
    }

    if (struct_literal_expr_matches_type(tokens, arg_start, arg_end, param_ty, ctx)) {
        return true;
    }

    const range = trim_parens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1) return false;

    const tok = tokens[range.start];
    if (tok.kind == .ident) {
        if (error_enum_branch_value(tokens, param_ty, tok.lexeme) != null) return true;
        if (value_enum_branch_value(ctx, tokens, param_ty, tok.lexeme) != null) return true;
        if (find_struct_local(locals.struct_locals.items, tok.lexeme)) |struct_local| {
            return std.mem.eql(u8, struct_local.ty, param_ty);
        }
    }
    if (tok.kind == .number) {
        return is_core_integer_scalar(param_ty) or is_core_float_scalar(param_ty);
    }
    if (tok.kind == .string) {
        return std.mem.eql(u8, param_ty, "text") or storage_elem_type_from_name(param_ty) != null;
    }
    if (tok.kind == .ident and (std.mem.eql(u8, tok.lexeme, "true") or std.mem.eql(u8, tok.lexeme, "false"))) {
        return std.mem.eql(u8, param_ty, "bool");
    }
    return false;
}

pub fn infer_put_call_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return null;
    if (find_storage_primitive_local(locals.storage_locals.items, tokens[start_idx].lexeme)) |storage| return storage.ty;
    return null;
}

pub fn call_args_match_variadic_tail(tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, elem_ty: []const u8) bool {
    if (args_start >= args_end) return true;
    if (tok_eq(tokens[args_start], "...")) {
        const rest_start = args_start + 1;
        if (find_arg_end(tokens, rest_start, args_end) != args_end) return false;
        if (rest_start + 1 != args_end or tokens[rest_start].kind != .ident) return false;
        const rest = find_storage_primitive_local(locals.storage_locals.items, tokens[rest_start].lexeme) orelse return false;
        return std.mem.eql(u8, rest.elem_ty, elem_ty);
    }

    var arg_start = args_start;
    while (arg_start < args_end) {
        const arg_end = find_arg_end(tokens, arg_start, args_end);
        if (arg_end == arg_start) return false;
        if (!call_arg_matches_param(tokens, arg_start, arg_end, locals, ctx, elem_ty)) return false;
        arg_start = arg_end;
        if (arg_start < args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }
    return true;
}

pub fn call_arg_matches_union_param(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, locals: *const LocalSet, ctx: CodegenContext, param_ty: []const u8) bool {
    const range = trim_parens(tokens, arg_start, arg_end);
    if (range.start >= range.end) return false;
    if (range.end == range.start + 1 and tok_eq(tokens[range.start], "nil")) {
        return union_type_name_has_branch(param_ty, "nil");
    }
    if (infer_expr_type(tokens, arg_start, arg_end, locals, ctx)) |arg_ty| {
        if (codegen_types_compatible(param_ty, arg_ty)) return true;
        return union_type_name_has_branch(param_ty, arg_ty);
    }
    return false;
}

pub fn union_type_name_has_branch(ty: []const u8, branch_ty: []const u8) bool {
    var branch_start: usize = 0;
    while (branch_start < ty.len) {
        const branch_end = find_top_level_type_separator_from(ty, branch_start, '|') orelse ty.len;
        if (std.mem.eql(u8, ty[branch_start..branch_end], branch_ty)) return true;
        branch_start = branch_end + 1;
    }
    return false;
}

pub fn infer_field_get_call_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, end_idx);
    if (field_end != end_idx) return null;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return null;

    const struct_local = find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null;
    const meta = find_field_meta_local(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return null;
    if (!std.mem.eql(u8, type_base_name(struct_local.ty), meta.struct_name)) return null;
    const field = field_from_meta(ctx, meta) orelse return null;
    return field.ty;
}

pub fn func_variadic_elem_type(param: FuncParam) []const u8 {
    if (!param.variadic) return param.ty;
    return param.ty;
}

pub fn infer_field_set_call_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return null;
    if (field_end >= end_idx or !tok_eq(tokens[field_end], ",")) return null;
    if (find_arg_end(tokens, field_end + 1, end_idx) != end_idx) return null;
    return (find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null).ty;
}

pub fn find_field_meta_local(locals: []const FieldMetaLocal, name: []const u8) ?FieldMetaLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

pub fn struct_literal_expr_matches_type(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, param_ty: []const u8, ctx: CodegenContext) bool {
    const range = trim_parens(tokens, arg_start, arg_end);
    const open_brace = struct_literal_open_rhs(tokens, range.start, range.end) orelse return false;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", range.end) catch return false;
    if (close_brace + 1 != range.end) return false;
    if (tokens[range.start].kind != .ident) return false;
    const literal_base = tokens[range.start].lexeme;
    if (!std.mem.eql(u8, type_base_name(param_ty), literal_base)) return false;
    return find_struct_decl(ctx.structs, param_ty) != null;
}

pub fn infer_get_call_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return null;

    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, end_idx);
    if (infer_tuple_field_path_get_type(tokens, start_idx, end_idx, first_end, locals, ctx)) |tuple_ty| return tuple_ty;
    if (second_end != end_idx) {
        return infer_path_get_call_type(tokens, start_idx, end_idx, first_end, locals, ctx);
    }

    if (second_end == second_start + 1 and is_dot_ident(tokens[second_start].lexeme)) {
        if (infer_managed_struct_expr_field_type(tokens, start_idx, first_end, tokens[second_start].lexeme, locals, ctx)) |field_ty| {
            return field_ty;
        }
    }

    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) {
        const storage_ty = infer_expr_type(tokens, start_idx, first_end, locals, ctx) orelse return null;
        if (storage_elem_type_from_name(storage_ty)) |elem_ty| return elem_ty;
        return null;
    }

    const name = tokens[start_idx].lexeme;
    if (find_storage_primitive_local(locals.storage_locals.items, name)) |storage| return storage.elem_ty;

    if (find_struct_local(locals.struct_locals.items, name)) |struct_local| {
        if (is_tuple_type_name(struct_local.ty)) {
            const elem_info = tuple_get_element_info(tokens, second_start, second_end, struct_local.ty) orelse return null;
            return elem_info.ty;
        }
    }

    if (second_end != second_start + 1 or !is_dot_ident(tokens[second_start].lexeme)) return null;

    const field_name = public_decl_name(tokens[second_start].lexeme);
    if (find_struct_local(locals.struct_locals.items, name)) |struct_local| {
        if (find_local_field_type(locals.locals.items, struct_local.name, field_name)) |field_ty| return field_ty;
        const decl = find_struct_decl(ctx.structs, struct_local.ty) orelse return null;
        return find_struct_field_type(decl, field_name);
    }
    if (find_union_local(locals.union_locals.items, name)) |union_local| {
        const payload = union_local_default_struct_payload(tokens, ctx, union_local) orelse return null;
        return find_struct_field_type(payload.decl, field_name);
    }
    return null;
}

pub fn lambda_expr_shape(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?LambdaExprShape {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.start >= range.end or !tok_eq(tokens[range.start], "(")) return null;
    const close_params = find_matching_in_range(tokens, range.start, "(", ")", range.end) catch return null;
    const body_start = lambda_body_start(tokens, close_params + 1, range.end) orelse return null;
    if (body_start >= range.end) return null;
    if (tok_eq(tokens[body_start], "{")) {
        const close_block = find_matching_in_range(tokens, body_start, "{", "}", range.end) catch return null;
        if (close_block + 1 != range.end) return null;
        return .{
            .open_params = range.start,
            .close_params = close_params,
            .body_start = body_start + 1,
            .body_end = close_block,
            .is_block = true,
        };
    }
    return .{
        .open_params = range.start,
        .close_params = close_params,
        .body_start = body_start,
        .body_end = range.end,
        .is_block = false,
    };
}

pub fn lambda_param_count(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;
    var count: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) count += 1;
        seg_start = i + 1;
    }
    return count;
}

pub fn callback_binding_has_same_concrete_arg(left: CallbackBinding, right: CallbackBinding) bool {
    if (left.kind != right.kind) return false;
    if (!callback_bindings_have_same_shape(left.shape, right.shape)) return false;
    return switch (left.kind) {
        .lambda => module_tokens_equal(left.arg_tokens, right.arg_tokens) and left.arg_start == right.arg_start and left.arg_end == right.arg_end,
        .func_ref => blk: {
            const left_name = left.func_name orelse break :blk false;
            const right_name = right.func_name orelse break :blk false;
            break :blk module_tokens_equal(left.arg_tokens, right.arg_tokens) and same_callable_source_name(left_name, right_name);
        },
    };
}

pub fn value_enum_branch_value(
    ctx: CodegenContext,
    tokens: []const lexer.Token,
    enum_name: []const u8,
    branch_name: []const u8,
) ?[]const u8 {
    if (find_value_enum_decl(ctx.value_enums, enum_name)) |decl| {
        if (find_value_enum_branch_value(decl, branch_name)) |value| return value;
    }
    const import_ref = find_codegen_import_by_alias(tokens, branch_name) orelse return null;
    for (ctx.modules) |module| {
        if (!value_enum_source_matches_import(module.tokens, import_ref)) continue;
        const enum_idx = find_value_enum_decl_line_by_branch(module.tokens, import_ref.target) orelse return null;
        if (!value_enum_type_matches_import_alias(ctx, module.tokens, enum_idx, enum_name)) return null;
        return value_enum_branch_value_in_line(module.tokens, enum_idx, import_ref.target);
    }
    return null;
}

pub fn infer_tuple_field_path_get_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const field_ty = tuple_field_path_type(tokens, start_idx, end_idx, first_end, locals, ctx) orelse return null;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, end_idx);
    const index_start = field_end + 1;
    const index_end = find_arg_end(tokens, index_start, end_idx);
    const elem_info = tuple_get_element_info(tokens, index_start, index_end, field_ty) orelse return null;
    return elem_info.ty;
}

pub fn append_managed_struct_field_meta_local(allocator: std.mem.Allocator, out: *LocalSet, base: []const u8, field: []const u8, ty: []const u8) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, public_decl_name(field) });
    try out.owned_names.append(allocator, name);
    try out.locals.append(allocator, .{
        .name = name,
        .ty = ty,
        .emit_decl = false,
        .release_on_scope_exit = false,
    });
}

pub fn field_from_meta(ctx: CodegenContext, meta: FieldMetaLocal) ?StructField {
    const decl = find_struct_decl(ctx.structs, meta.struct_name) orelse return null;
    if (meta.decl_index >= decl.fields.len) return null;
    return decl.fields[meta.decl_index];
}

pub fn find_struct_field(decl: StructDecl, field_name: []const u8) ?StructField {
    for (decl.fields) |field| {
        if (std.mem.eql(u8, public_decl_name(field.name), field_name)) return field;
    }
    return null;
}

pub fn union_local_default_payload_type(tokens: []const lexer.Token, union_local: UnionLocal) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (is_error_like_type(tokens, branch.ty)) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

pub fn union_local_default_struct_payload(tokens: []const lexer.Token, ctx: CodegenContext, union_local: UnionLocal) ?UnionStructPayload {
    var matched: ?UnionStructPayload = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (is_error_like_type(tokens, branch.ty)) continue;
        const decl = find_struct_decl(ctx.structs, branch.ty) orelse continue;
        if (find_struct_layout(ctx.struct_layouts, branch.ty) == null and branch.payload_len != decl.fields.len) continue;
        if (find_struct_layout(ctx.struct_layouts, branch.ty) != null and branch.payload_len != 1) continue;
        if (matched != null) return null;
        matched = .{ .branch = branch, .decl = decl };
    }
    return matched;
}

pub fn find_narrowed_union_type(locals: []const NarrowedUnionLocal, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_name_matches(local.name, local.source_name, name)) return local.ty;
    }
    return null;
}

pub fn is_dot_ident(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}

const CodegenImportRef = model.CodegenImportRef;
const wasi_lowering = codegen_wasi_registry.wasi_lowering;
pub fn is_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq(tokens[idx], "=") and tok_eq(tokens[idx + 1], ">");
}

pub fn lambda_body_start(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) ?usize {
    if (is_arrow_at(tokens, start_idx)) return start_idx + 2;
    if (start_idx < limit_idx and tok_eq(tokens[start_idx], "{")) return start_idx;
    if (start_idx >= limit_idx or !is_return_arrow_at(tokens, start_idx)) return null;

    var i = start_idx + 2;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    while (i < limit_idx) : (i += 1) {
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (depth_angle == 0 and depth_paren == 0 and is_arrow_at(tokens, i)) return i + 2;
        if (depth_angle == 0 and depth_paren == 0 and tok_eq(tokens[i], "{")) return i;
    }
    return null;
}

pub fn lambda_param_type_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 >= end_idx) return null;
    return simple_type_name(tokens, start_idx + 1, end_idx);
}

pub fn lambda_explicit_return_type(tokens: []const lexer.Token, lambda: LambdaExprShape) ?[]const u8 {
    if (!is_return_arrow_at(tokens, lambda.close_params + 1)) return null;
    const ret_start = lambda.close_params + 3;
    const ret_end = if (lambda.is_block) lambda.body_start - 1 else lambda.body_start - 2;
    if (ret_start >= ret_end) return null;
    return simple_type_name(tokens, ret_start, ret_end);
}

pub fn append_typed_local_with_decl(allocator: std.mem.Allocator, locals: *LocalSet, name: []const u8, ty: []const u8, ctx: CodegenContext, emit_decl: bool) !void {
    if (managed_payload_elem_type_from_name(ty)) |elem_ty| {
        try locals.append_borrowed_local(allocator, name, ty, emit_decl);
        try locals.storage_locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .elem_ty = elem_ty,
        });
        return;
    }

    if (find_struct_decl(ctx.structs, ty)) |decl| {
        try locals.struct_locals.append(allocator, .{
            .name = name,
            .ty = ty,
        });
        if (find_struct_layout(ctx.struct_layouts, ty) != null) {
            try locals.append_borrowed_local(allocator, name, ty, emit_decl);
            for (decl.fields) |field| {
                const field_ty = try substitute_struct_field_type(allocator, decl, ty, field.ty, &locals.owned_names);
                try append_managed_struct_field_meta_local(allocator, locals, name, field.name, field_ty);
            }
            return;
        }
        for (decl.fields) |field| {
            const field_ty = try substitute_struct_field_type(allocator, decl, ty, field.ty, &locals.owned_names);
            try append_borrowed_local_field(allocator, locals, ctx.entry_tokens, ctx, name, field.name, field_ty);
        }
        return;
    }

    try locals.append_borrowed_local(allocator, name, ty, emit_decl);
}

pub fn append_typed_local(allocator: std.mem.Allocator, locals: *LocalSet, name: []const u8, ty: []const u8, ctx: CodegenContext) !void {
    return append_typed_local_with_decl(allocator, locals, name, ty, ctx, false);
}

pub fn infer_lambda_expr_return_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, lambda: LambdaExprShape, shape: FuncTypeShape, locals: *const LocalSet, ctx: CodegenContext) !?[]const u8 {
    if (lambda.close_params + 1 < tokens.len and is_return_arrow_at(tokens, lambda.close_params + 1)) {
        return lambda_explicit_return_type(tokens, lambda);
    }
    if (lambda.is_block) return "nil";
    if (shape.param_types.len == 0) {
        return infer_expr_type(tokens, lambda.body_start, lambda.body_end, locals, ctx);
    }

    var lambda_locals = try clone_local_set(allocator, locals);
    defer lambda_locals.deinit(allocator);

    var seg_start = lambda.open_params + 1;
    var seg_idx: usize = 0;
    var i = lambda.open_params + 1;
    while (i <= lambda.close_params) : (i += 1) {
        if (i < lambda.close_params and !is_top_level_comma_any(tokens, i, lambda.open_params + 1, lambda.close_params)) continue;
        if (seg_start < i) {
            if (seg_idx >= shape.param_types.len) return null;
            const param_ty = shape.param_types[seg_idx] orelse return null;
            if (tokens[seg_start].kind != .ident) return null;
            try append_typed_local(allocator, &lambda_locals, tokens[seg_start].lexeme, param_ty, ctx);
            seg_idx += 1;
        }
        seg_start = i + 1;
    }
    if (seg_idx != shape.param_types.len) return null;
    return infer_expr_type(tokens, lambda.body_start, lambda.body_end, &lambda_locals, ctx);
}

pub fn clone_local_set(allocator: std.mem.Allocator, locals: *const LocalSet) !LocalSet {
    var out = LocalSet{};
    try out.locals.appendSlice(allocator, locals.locals.items);
    try out.struct_locals.appendSlice(allocator, locals.struct_locals.items);
    try out.storage_locals.appendSlice(allocator, locals.storage_locals.items);
    for (locals.union_locals.items) |union_local| {
        try out.union_locals.append(allocator, .{
            .name = union_local.name,
            .source_name = union_local.source_name,
            .layout = union_local.layout,
            .owns_layout = false,
            .origin = union_local.origin,
        });
    }
    try out.narrowed_union_locals.appendSlice(allocator, locals.narrowed_union_locals.items);
    try out.field_meta_locals.appendSlice(allocator, locals.field_meta_locals.items);
    out.local_name_prefix = locals.local_name_prefix;
    return out;
}

pub fn callback_function_matches_shape(func: FuncDecl, shape: FuncTypeShape) bool {
    if (func.params.len != shape.param_types.len) return false;
    for (shape.param_types, 0..) |target_ty, idx| {
        const expected = target_ty orelse continue;
        if (!std.mem.eql(u8, func.params[idx].ty, expected)) return false;
    }
    if (shape.return_type) |ret_ty| {
        if (std.mem.eql(u8, ret_ty, "nil")) {
            return func.result == null or std.mem.eql(u8, func.result.?, "nil");
        }
        const actual_ret = func.result orelse return false;
        if (!std.mem.eql(u8, actual_ret, ret_ty)) return false;
    }
    return true;
}

pub fn callback_lambda_return_matches_shape(tokens: []const lexer.Token, lambda: LambdaExprShape, shape: FuncTypeShape, locals: *const LocalSet, ctx: CodegenContext) bool {
    if (shape.return_type) |ret_ty| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const lambda_ret = infer_lambda_expr_return_type(arena.allocator(), tokens, lambda, shape, locals, ctx) catch return false;
        if (lambda_ret) |actual| {
            if (std.mem.eql(u8, actual, "nil")) return std.mem.eql(u8, ret_ty, "nil");
            return std.mem.eql(u8, ret_ty, actual);
        }
        return false;
    }
    if (!lambda.is_block) return true;
    if (is_return_arrow_at(tokens, lambda.close_params + 1)) {
        if (lambda_explicit_return_type(tokens, lambda)) |lambda_ret| {
            return std.mem.eql(u8, lambda_ret, "nil");
        }
        return false;
    }
    return true;
}

pub fn find_callback_ref_func(tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8, shape: FuncTypeShape) ?FuncDecl {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, tokens)) continue;
        if (!same_callable_source_name(func.source_name, name)) continue;
        if (callback_function_matches_shape(func, shape)) return func;
    }
    return null;
}

pub fn lambda_explicit_types_match_shape(tokens: []const lexer.Token, lambda: LambdaExprShape, shape: FuncTypeShape) bool {
    var seg_start = lambda.open_params + 1;
    var seg_idx: usize = 0;
    var i = lambda.open_params + 1;
    while (i <= lambda.close_params) : (i += 1) {
        if (i < lambda.close_params and !is_top_level_comma_any(tokens, i, lambda.open_params + 1, lambda.close_params)) continue;
        if (seg_start < i) {
            if (seg_idx >= shape.param_types.len) return false;
            if (lambda_param_type_name(tokens, seg_start, i)) |ty| {
                const expected = shape.param_types[seg_idx] orelse return false;
                if (!std.mem.eql(u8, expected, ty)) return false;
            }
            seg_idx += 1;
        }
        seg_start = i + 1;
    }
    return seg_idx == shape.param_types.len;
}

pub fn type_base_name(ty: []const u8) []const u8 {
    return type_util.type_base_name(ty);
}

pub fn value_enum_type_matches_import_alias(ctx: CodegenContext, tokens: []const lexer.Token, enum_idx: usize, expected_name: []const u8) bool {
    const source_name = public_decl_name(tokens[enum_idx].lexeme);
    if (std.mem.eql(u8, source_name, expected_name)) return true;
    const decl = find_value_enum_decl(ctx.value_enums, expected_name) orelse return false;
    return std.mem.eql(u8, decl.source_name, source_name);
}

pub fn find_value_enum_branch_value(decl: ValueEnumDecl, branch_name: []const u8) ?[]const u8 {
    for (decl.branches) |branch| {
        if (std.mem.eql(u8, branch.name, branch_name)) return branch.value;
    }
    return null;
}

pub fn value_enum_branch_value_in_line(tokens: []const lexer.Token, enum_idx: usize, branch_name: []const u8) ?[]const u8 {
    const line_end = find_line_end(tokens, enum_idx);
    var j = enum_idx + 3;
    while (j + 3 < line_end) {
        if (tok_eq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind == .ident and std.mem.eql(u8, public_decl_name(tokens[j].lexeme), branch_name)) return tokens[j + 2].lexeme;
        j += 4;
    }
    return null;
}

pub fn value_enum_source_matches_import(tokens: []const lexer.Token, import_ref: CodegenImportRef) bool {
    if (find_value_enum_decl_line_by_name(tokens, import_ref.target) != null) return true;
    return find_value_enum_decl_line_by_branch(tokens, import_ref.target) != null;
}

pub fn managed_payload_elem_type_from_name(ty: []const u8) ?[]const u8 {
    return type_util.managed_payload_elem_type_from_name(ty);
}

pub fn abs_result_type(source_ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, source_ty, "i8")) return "u8";
    if (std.mem.eql(u8, source_ty, "i16")) return "u16";
    if (std.mem.eql(u8, source_ty, "i32")) return "u32";
    if (std.mem.eql(u8, source_ty, "i64")) return "u64";
    if (std.mem.eql(u8, source_ty, "isize")) return "usize";
    if (std.mem.eql(u8, source_ty, "f32")) return "f32";
    if (std.mem.eql(u8, source_ty, "f64")) return "f64";
    return null;
}

pub fn infer_first_arg_type_or_default_s32(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = find_arg_end(tokens, args_start, args_end);
    return infer_expr_type(tokens, args_start, first_end, locals, ctx) orelse "i32";
}

pub fn wasi_do_result_type(import: WasiHostImport) ?[]const u8 {
    const lowering = wasi_lowering(import) orelse return null;
    if (lowering.result_storage_elem) |elem_ty| return storage_type_name_for_elem(elem_ty);
    if (lowering.result_list_preopen) return "[Tuple<Dir,text>]";
    if (lowering.result_record) |record| return record;
    return import.result;
}

pub fn memory_load_result_type(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "load_u8")) return "u8";
    if (std.mem.eql(u8, name, "load_i8")) return "i8";
    if (std.mem.eql(u8, name, "load_u16_le")) return "u16";
    if (std.mem.eql(u8, name, "load_i16_le")) return "i16";
    if (std.mem.eql(u8, name, "load_u32_le")) return "u32";
    if (std.mem.eql(u8, name, "load_i32_le")) return "i32";
    if (std.mem.eql(u8, name, "load_u64_le")) return "u64";
    if (std.mem.eql(u8, name, "load_i64_le")) return "i64";
    return null;
}

pub fn infer_path_get_call_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    var current_ty = infer_expr_type(tokens, start_idx, first_end, locals, ctx) orelse return null;
    var segment_start = first_end + 1;
    while (segment_start < end_idx) {
        const segment_end = find_arg_end(tokens, segment_start, end_idx);
        if (segment_end == segment_start) return null;
        const has_more = segment_end < end_idx;
        if (has_more and !tok_eq(tokens[segment_end], ",")) return null;

        if (segment_end == segment_start + 1 and is_dot_ident(tokens[segment_start].lexeme)) {
            const decl = find_struct_decl(ctx.structs, current_ty) orelse return null;
            const field_ty = find_concrete_struct_field_type_no_alloc(decl, current_ty, public_decl_name(tokens[segment_start].lexeme)) orelse return null;
            current_ty = substitute_generic_type(field_ty, ctx.type_bindings);
        } else if (is_tuple_type_name(current_ty)) {
            const elem_info = tuple_get_element_info(tokens, segment_start, segment_end, current_ty) orelse return null;
            current_ty = elem_info.ty;
        } else {
            current_ty = storage_elem_type_from_name(current_ty) orelse return null;
        }

        if (!has_more) return current_ty;
        segment_start = segment_end + 1;
    }
    return null;
}

pub fn infer_managed_struct_expr_field_type(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    dot_field: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (value_end == value_start + 1 and tokens[value_start].kind == .ident) return null;
    const struct_ty = infer_expr_type(tokens, value_start, value_end, locals, ctx) orelse return null;
    if (find_struct_layout(ctx.struct_layouts, struct_ty) == null) return null;
    const decl = find_struct_decl(ctx.structs, struct_ty) orelse return null;
    return find_concrete_struct_field_type_no_alloc(decl, struct_ty, public_decl_name(dot_field));
}

pub fn find_concrete_struct_field_type_no_alloc(decl: StructDecl, concrete_ty: []const u8, field_name: []const u8) ?[]const u8 {
    const field = find_struct_field(decl, field_name) orelse return null;
    if (decl.type_params.len == 0) return field.ty;
    for (decl.type_params, 0..) |type_param, idx| {
        if (!std.mem.eql(u8, field.ty, type_param)) continue;
        return generic_type_arg_at(concrete_ty, idx);
    }
    return field.ty;
}

pub fn generic_type_arg_at(concrete_ty: []const u8, target_idx: usize) ?[]const u8 {
    return type_util.generic_type_arg_at(concrete_ty, target_idx);
}
