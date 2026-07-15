//! Collect shared pure helpers (extracted from codegen_collect).
//! Declaration / layout collection for codegen (no emit).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");

const align_up = codegen_tokens.align_up;
const append_fmt = codegen_names.append_fmt;
const append_mangled_type_name = codegen_names.append_mangled_type_name;
const compact_token_text = codegen_tokens.compact_token_text;
const find_arg_end = codegen_tokens.find_arg_end;
const find_line_end = codegen_tokens.find_line_end;
const find_line_start = codegen_tokens.find_line_start;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_token = codegen_tokens.find_token;
const find_top_level_token = codegen_tokens.find_top_level_token;
const is_base_int_type_name = codegen_names.is_base_int_type_name;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;
const is_error_type_name = codegen_names.is_error_type_name;
const is_line_start = codegen_tokens.is_line_start;
const is_public_type_name = codegen_names.is_public_type_name;
const is_user_func_decl_start = codegen_tokens.is_user_func_decl_start;
const module_scoped_symbol_name = codegen_names.module_scoped_symbol_name;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const public_decl_name = codegen_names.public_decl_name;
const string_token_body = codegen_tokens.string_token_body;
const tok_eq = codegen_tokens.tok_eq;
const free_union_layout = codegen_union_layout.free_union_layout;
const find_local_origin = context.find_local_origin;
const find_top_level_type_separator = codegen_tokens.find_top_level_type_separator;
const find_type_arg_end = codegen_tokens.find_type_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const find_top_level_type_separator_from = codegen_tokens.find_top_level_type_separator_from;
const Range = codegen_tokens.Range;

const free_struct_decl = model.free_struct_decl;
const free_struct_decls = model.free_struct_decls;

const GenericTypeArgsRange = type_util.GenericTypeArgsRange;

const TokenRange = struct {
    tokens: []const lexer.Token,
    start: usize,
    end: usize,
};

const find_codegen_import_by_alias = codegen_imports.find_codegen_import_by_alias;
const collect_start_body_calls = codegen_imports.collect_start_body_calls;
const collect_test_body_calls = codegen_imports.collect_test_body_calls;
const collect_all_function_body_calls = codegen_imports.collect_all_function_body_calls;
const collect_function_body_calls = codegen_imports.collect_function_body_calls;
const find_imported_module_index = codegen_imports.find_imported_module_index;
const find_payload_enum_decl = codegen_imports.find_payload_enum_decl;
const find_root_module_index = codegen_imports.find_root_module_index;
const find_value_enum_decl = codegen_imports.find_value_enum_decl;
const find_value_enum_decl_line_by_branch = codegen_imports.find_value_enum_decl_line_by_branch;
const find_value_enum_decl_line_by_name = codegen_imports.find_value_enum_decl_line_by_name;
const has_reach_visit = codegen_imports.has_reach_visit;
const imported_alias_context_for_tokens = codegen_imports.imported_alias_context_for_tokens;
const is_payload_enum_decl_start = codegen_imports.is_payload_enum_decl_start;
const is_value_enum_decl_start = codegen_imports.is_value_enum_decl_start;
const parse_codegen_import = codegen_imports.parse_codegen_import;

const is_managed_payload_type = type_util.is_managed_payload_type;
const is_tuple_type_name = type_util.is_tuple_type_name;
const is_tuple_packable_leaf_type = type_util.is_tuple_packable_leaf_type;
const managed_payload_elem_type_from_name = type_util.managed_payload_elem_type_from_name;
const tuple_arity = type_util.tuple_arity;
const tuple_element_type_at = type_util.tuple_element_type_at;
const tuple_scalar_leaf_storage_byte_width = type_util.tuple_scalar_leaf_storage_byte_width;
const type_base_name = type_util.type_base_name;
const type_payload_alignment = type_util.type_payload_alignment;
const type_payload_bytes = type_util.type_payload_bytes;

const CallbackBinding = model.CallbackBinding;
const CallbackBindingKind = model.CallbackBindingKind;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const CodegenImportPrefix = model.CodegenImportPrefix;
const CodegenImportRef = model.CodegenImportRef;
const FuncBodyShape = model.FuncBodyShape;
const FuncDecl = model.FuncDecl;
const FuncParam = model.FuncParam;
const FuncResultItem = model.FuncResultItem;
const FuncResultParse = model.FuncResultParse;
const FuncTypeShape = model.FuncTypeShape;
const GenericTypeBinding = model.GenericTypeBinding;
const HostImport = model.HostImport;
const ImportedAliasContext = model.ImportedAliasContext;
const LambdaExprShape = model.LambdaExprShape;
const LocalSet = context.LocalSet;
const ManagedFieldOffset = model.ManagedFieldOffset;
const NO_RESULT_ITEMS = model.NO_RESULT_ITEMS;
const OwnedFuncTypeShape = model.OwnedFuncTypeShape;
const ParsedCodegenType = model.ParsedCodegenType;
const PayloadEnumCase = model.PayloadEnumCase;
const PayloadEnumDecl = model.PayloadEnumDecl;
const ReachVisit = model.ReachVisit;
const StructDecl = model.StructDecl;
const StructErrorResult = model.StructErrorResult;
const StructField = model.StructField;
const StructLayout = model.StructLayout;
const TYPE_ID_FIRST_STRUCT = constants.TYPE_ID_FIRST_STRUCT;
const ValueEnumBranch = model.ValueEnumBranch;
const ValueEnumDecl = model.ValueEnumDecl;
const storage_type_name_for_elem = context.storage_type_name_for_elem;
const TYPE_ID_STORAGE_MANAGED = constants.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_STORAGE_U8 = constants.TYPE_ID_STORAGE_U8;

const UnionBranch = codegen_union_layout.UnionBranch;
const UnionLayout = codegen_union_layout.UnionLayout;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;

pub fn stmt_contains_storage_agg_literal(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], ".") and tok_eq(tokens[i + 1], "{")) return true;
    }
    return false;
}

fn type_args_close_idx(tokens: []const lexer.Token, open_angle: usize, end_idx: usize) ?usize {
    var depth: usize = 0;
    var i = open_angle;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "<")) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], ">")) continue;
        if (depth == 0) return null;
        depth -= 1;
        if (depth == 0) return i;
    }
    return null;
}

pub fn stmt_contains_struct_literal_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and tok_eq(tokens[i + 1], "{")) return true;
        if (tokens[i].kind == .ident and tok_eq(tokens[i + 1], "<")) {
            const close = type_args_close_idx(tokens, i + 1, end_idx) orelse continue;
            if (close + 1 < end_idx and tok_eq(tokens[close + 1], "{")) return true;
        }
        if (tok_eq(tokens[i], ".") and tok_eq(tokens[i + 1], "{")) return true;
    }
    return false;
}

pub fn token_range_uses_ident(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, name: []const u8) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i].lexeme, name)) return true;
    }
    return false;
}

pub fn parse_codegen_type_expr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    owned_types: *std.ArrayList([]const u8),
) !?ParsedCodegenType {
    if (start_idx >= end_idx) return null;

    if (tok_eq(tokens[start_idx], "[")) {
        const close_bracket = find_matching_in_range(tokens, start_idx, "[", "]", end_idx) catch return null;
        if (close_bracket <= start_idx + 1) return null;
        if (close_bracket == start_idx + 2 and tokens[start_idx + 1].kind == .ident) {
            if (storage_type_name_for_elem(tokens[start_idx + 1].lexeme)) |storage_ty| {
                return .{ .ty = storage_ty, .next_idx = close_bracket + 1 };
            }
        }
        const ty = try compact_token_text(allocator, tokens, start_idx, close_bracket + 1);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return .{ .ty = ty, .next_idx = close_bracket + 1 };
    }

    if (tokens[start_idx].kind != .ident) return null;
    if (start_idx + 1 < end_idx and tok_eq(tokens[start_idx + 1], "<")) {
        const close_angle = find_matching_in_range(tokens, start_idx + 1, "<", ">", end_idx) catch return null;
        const ty = try compact_token_text(allocator, tokens, start_idx, close_angle + 1);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return .{ .ty = ty, .next_idx = close_angle + 1 };
    }

    return .{ .ty = tokens[start_idx].lexeme, .next_idx = start_idx + 1 };
}

pub fn bind_generic_type(
    allocator: std.mem.Allocator,
    bindings: *std.ArrayList(GenericTypeBinding),
    name: []const u8,
    ty: []const u8,
    owned_types: *std.ArrayList([]const u8),
) !bool {
    for (bindings.items) |binding| {
        if (!std.mem.eql(u8, binding.name, name)) continue;
        return std.mem.eql(u8, binding.ty, ty);
    }
    const owned_ty = try allocator.dupe(u8, ty);
    errdefer allocator.free(owned_ty);
    try owned_types.append(allocator, owned_ty);
    try bindings.append(allocator, .{ .name = name, .ty = owned_ty });
    return true;
}

pub fn find_generic_binding(bindings: []const GenericTypeBinding, name: []const u8) ?GenericTypeBinding {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}

pub fn substitute_generic_type_owned(
    allocator: std.mem.Allocator,
    ty: []const u8,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8),
) ![]const u8 {
    if (find_generic_binding(bindings, ty)) |binding| return binding.ty;
    if (!type_contains_generic_binding(ty, bindings)) return ty;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < ty.len) {
        if (!is_type_ident_start(ty[i])) {
            try out.append(allocator, ty[i]);
            i += 1;
            continue;
        }

        const ident_start = i;
        i += 1;
        while (i < ty.len and is_type_ident_part(ty[i])) i += 1;
        const ident = ty[ident_start..i];
        if (find_generic_binding(bindings, ident)) |binding| {
            try out.appendSlice(allocator, binding.ty);
        } else {
            try out.appendSlice(allocator, ident);
        }
    }

    const owned = try out.toOwnedSlice(allocator);
    errdefer allocator.free(owned);
    try owned_types.append(allocator, owned);
    return owned;
}

pub fn type_contains_generic_binding(ty: []const u8, bindings: []const GenericTypeBinding) bool {
    var i: usize = 0;
    while (i < ty.len) {
        if (!is_type_ident_start(ty[i])) {
            i += 1;
            continue;
        }
        const ident_start = i;
        i += 1;
        while (i < ty.len and is_type_ident_part(ty[i])) i += 1;
        if (find_generic_binding(bindings, ty[ident_start..i]) != null) return true;
    }
    return false;
}

pub fn is_type_ident_start(ch: u8) bool {
    return ch == '_' or (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z');
}

pub fn is_type_ident_part(ch: u8) bool {
    return is_type_ident_start(ch) or (ch >= '0' and ch <= '9');
}

pub fn generic_type_args_range(ty: []const u8) ?GenericTypeArgsRange {
    return type_util.generic_type_args_range(ty);
}

pub fn parse_func_body_shape(tokens: []const lexer.Token, close_params: usize) !FuncBodyShape {
    const after_params = close_params + 1;
    if (after_params < tokens.len and tok_eq(tokens[after_params], "{")) {
        const close_body = try find_matching(tokens, after_params, "{", "}");
        return .{
            .result_start = after_params,
            .result_end = after_params,
            .body_start = after_params + 1,
            .body_end = close_body,
            .arrow = false,
            .next_idx = close_body,
        };
    }

    if (after_params + 1 >= tokens.len or !tok_eq(tokens[after_params], "-") or !tok_eq(tokens[after_params + 1], ">")) {
        return error.NoMatchingCall;
    }

    const result_start = after_params + 2;
    if (result_start >= tokens.len) return error.NoMatchingCall;
    const arrow_idx = find_top_level_token(tokens, result_start, find_line_end(tokens, close_params), "=") orelse {
        const open_body = find_token(tokens, result_start, tokens.len, "{") orelse return error.NoMatchingCall;
        const close_body = try find_matching(tokens, open_body, "{", "}");
        return .{
            .result_start = result_start,
            .result_end = open_body,
            .body_start = open_body + 1,
            .body_end = close_body,
            .arrow = false,
            .next_idx = close_body,
        };
    };
    if (arrow_idx == result_start or arrow_idx + 1 >= tokens.len or !tok_eq(tokens[arrow_idx + 1], ">")) return error.NoMatchingCall;
    if (arrow_idx + 2 >= tokens.len) return error.NoMatchingCall;

    return .{
        .result_start = result_start,
        .result_end = arrow_idx,
        .body_start = arrow_idx + 2,
        .body_end = find_line_end(tokens, arrow_idx),
        .arrow = true,
        .next_idx = find_line_end(tokens, arrow_idx) - 1,
    };
}

pub fn parse_generic_inline_union_layout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    if (!has_top_level_token(tokens, start_idx, end_idx, "|")) return null;

    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);

    var next_non_nil_tag: usize = 1;
    var branch_start = start_idx;
    while (branch_start < end_idx) {
        if (tok_eq(tokens[branch_start], "|")) {
            branch_start += 1;
            continue;
        }

        const branch_end = find_top_level_token(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start) return null;
        const payload_start = payload_tys.items.len;

        if (branch_end == branch_start + 1 and tok_eq(tokens[branch_start], "nil")) {
            try branches.append(allocator, .{
                .ty = "nil",
                .tag = 0,
                .payload_start = payload_start,
                .payload_len = 0,
            });
            branch_start = branch_end;
            if (branch_start < end_idx and tok_eq(tokens[branch_start], "|")) branch_start += 1;
            continue;
        }
        const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, branch_start, branch_end, owned_types)) orelse return null;
        if (parsed_ty.next_idx != branch_end) return null;
        if (has_type_param_name(type_params, parsed_ty.ty)) {
            try payload_tys.append(allocator, parsed_ty.ty);
        } else {
            try append_union_branch_payload_types(allocator, tokens, parsed_ty.ty, structs, struct_layouts, &payload_tys);
        }
        try branches.append(allocator, .{
            .ty = parsed_ty.ty,
            .tag = next_non_nil_tag,
            .payload_start = payload_start,
            .payload_len = payload_tys.items.len - payload_start,
        });
        next_non_nil_tag += 1;

        branch_start = branch_end;
        if (branch_start < end_idx and tok_eq(tokens[branch_start], "|")) branch_start += 1;
    }

    if (branches.items.len < 2) return null;
    const source_ty = try compact_token_text(allocator, tokens, start_idx, end_idx);
    errdefer allocator.free(source_ty);
    try owned_types.append(allocator, source_ty);

    return .{
        .source_ty = source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}

pub fn has_type_param_name(type_params: []const []const u8, name: []const u8) bool {
    for (type_params) |type_param| {
        if (std.mem.eql(u8, type_param, name)) return true;
    }
    return false;
}

pub fn parse_struct_error_result_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
) ?StructErrorResult {
    if (start_idx + 3 != end_idx) return null;
    if (!tok_eq(tokens[start_idx + 1], "|")) return null;

    const left = tokens[start_idx].lexeme;
    const right = tokens[start_idx + 2].lexeme;
    if (tokens[start_idx].kind == .ident and tokens[start_idx + 2].kind == .ident) {
        if (is_unmanaged_scalar_struct(structs, struct_layouts, left) and is_error_like_type(tokens, right)) {
            return .{ .struct_name = left, .error_name = right };
        }
        if (is_error_like_type(tokens, left) and is_unmanaged_scalar_struct(structs, struct_layouts, right)) {
            return .{ .struct_name = right, .error_name = left };
        }
    }
    return null;
}

pub fn parse_union_type_layout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    const range = union_type_expr_range(allocator, tokens, start_idx, end_idx, imported_alias_ctx) orelse return null;
    return try parse_inline_union_layout(allocator, range.tokens, range.start, range.end, structs, struct_layouts, owned_types);
}

pub fn union_type_expr_range(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    imported_alias_ctx: ?ImportedAliasContext,
) ?TokenRange {
    if (has_top_level_token(tokens, start_idx, end_idx, "|")) return .{ .tokens = tokens, .start = start_idx, .end = end_idx };
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (local_union_alias_range(tokens, tokens[start_idx].lexeme)) |range| {
        return .{ .tokens = tokens, .start = range.start, .end = range.end };
    }
    return imported_union_alias_range(allocator, imported_alias_ctx, tokens, tokens[start_idx].lexeme);
}

pub fn local_union_alias_range(tokens: []const lexer.Token, name: []const u8) ?Range {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_line_start(tokens, i)) continue;
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!tok_eq(tokens[i + 1], "=")) continue;
        const line_end = find_line_end(tokens, i);
        const rhs_start = i + 2;
        if (!has_top_level_token(tokens, rhs_start, line_end, "|")) return null;
        return .{ .start = rhs_start, .end = line_end };
    }
    return null;
}

pub fn imported_union_alias_range(
    allocator: std.mem.Allocator,
    imported_alias_ctx: ?ImportedAliasContext,
    tokens: []const lexer.Token,
    name: []const u8,
) ?TokenRange {
    const ctx = imported_alias_context_for_tokens(imported_alias_ctx, tokens) orelse return null;
    const import_ref = find_codegen_import_by_alias(tokens, name) orelse return null;
    const child_idx = find_imported_module_index(allocator, ctx.graph, ctx.module_idx, import_ref) orelse return null;
    const child_tokens = ctx.graph.modules[child_idx].tokens;
    const range = local_union_alias_range(child_tokens, import_ref.target) orelse return null;
    return .{ .tokens = child_tokens, .start = range.start, .end = range.end };
}

pub fn append_union_branch_payload_types(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ty: []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    out: *std.ArrayList([]const u8),
) !void {
    if (find_struct_decl(structs, ty)) |decl| {
        if (find_struct_layout(struct_layouts, ty) == null) {
            for (decl.fields) |field| try out.append(allocator, field.ty);
            return;
        }
    }
    // Tuple-in-union: flatten leaf ABI slots (e.g. Tuple<[u8],bool> → [u8], bool).
    if (is_tuple_type_name(ty)) {
        try append_tuple_leaf_types_with_structs(allocator, ty, structs, out);
        return;
    }
    if (is_core_wasm_scalar(ty) or is_error_like_type(tokens, ty) or managed_payload_elem_type_from_name(ty) != null or find_struct_layout(struct_layouts, ty) != null) {
        try out.append(allocator, ty);
        return;
    }
    return error.NoMatchingCall;
}

pub fn has_top_level_token(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) bool {
    return find_top_level_token(tokens, start_idx, end_idx, lexeme) != null;
}

pub fn is_unmanaged_scalar_struct(
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    name: []const u8,
) bool {
    if (find_struct_layout(struct_layouts, name) != null) return false;
    const decl = find_struct_decl(structs, name) orelse return false;
    for (decl.fields) |field| {
        if (!is_core_wasm_scalar(field.ty)) return false;
    }
    return true;
}

pub fn is_error_like_type(tokens: []const lexer.Token, name: []const u8) bool {
    return is_error_enum_type(tokens, name) or error_nil_alias_target(tokens, name) != null or std.mem.endsWith(u8, name, "Error");
}

pub fn is_error_enum_type(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (tok_eq(tokens[i + 1], "error") and tok_eq(tokens[i + 2], "=")) return true;
    }
    return false;
}

pub fn error_nil_alias_target(tokens: []const lexer.Token, name: []const u8) ?[]const u8 {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 4 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!tok_eq(tokens[i + 1], "=")) continue;

        const line_end = find_line_end(tokens, i);
        if (i + 5 != line_end) return null;
        if (tokens[i + 2].kind == .ident and tok_eq(tokens[i + 3], "|") and tok_eq(tokens[i + 4], "nil") and
            is_error_enum_type_name_for_lowering(tokens, tokens[i + 2].lexeme))
        {
            return tokens[i + 2].lexeme;
        }
        if (tok_eq(tokens[i + 2], "nil") and tok_eq(tokens[i + 3], "|") and tokens[i + 4].kind == .ident and
            is_error_enum_type_name_for_lowering(tokens, tokens[i + 4].lexeme))
        {
            return tokens[i + 4].lexeme;
        }
        return null;
    }
    return null;
}

pub fn is_error_enum_type_name_for_lowering(tokens: []const lexer.Token, name: []const u8) bool {
    return is_error_enum_type(tokens, name) or std.mem.endsWith(u8, name, "Error");
}

pub fn func_param_abi_type(param: FuncParam) []const u8 {
    if (param.abi_ty) |abi_ty| return abi_ty;
    if (!param.variadic) return param.ty;
    return storage_type_name_for_elem(param.ty) orelse param.ty;
}

pub fn find_struct_decl(structs: []const StructDecl, name: []const u8) ?StructDecl {
    const lookup_name = type_base_name(name);
    for (structs) |decl| {
        if (std.mem.eql(u8, decl.name, lookup_name)) return decl;
    }
    return null;
}

pub fn find_struct_layout(layouts: []const StructLayout, name: []const u8) ?StructLayout {
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, name)) return layout;
    }
    const lookup_name = type_base_name(name);
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, lookup_name)) return layout;
    }
    return null;
}

pub fn is_top_level_struct_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!is_line_start(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[idx].lexeme, "start")) return false;
    return tok_eq(tokens[idx + 1], "{");
}

pub fn pure_scalar_struct_pack_width(decl: StructDecl, structs: []const StructDecl) ?usize {
    if (decl.fields.len == 0) return null;
    var offset: usize = 0;
    for (decl.fields) |field| {
        const field_ty = field.ty;
        if (type_util.is_managed_payload_type(field_ty)) return null;
        if (is_tuple_type_name(field_ty)) {
            // Nested Tuple inside pure-scalar struct: recursive width without managed.
            const w = tuple_pack_width_with_structs(field_ty, structs) orelse return null;
            offset = align_up(offset, type_payload_alignment(field_ty));
            offset += w;
            continue;
        }
        if (find_struct_decl(structs, field_ty)) |nested| {
            // Nested managed struct inside pure-scalar parent is not pure-scalar.
            if (struct_decl_has_managed_field(nested, structs)) return null;
            const w = pure_scalar_struct_pack_width(nested, structs) orelse return null;
            offset = align_up(offset, 1);
            offset += w;
            continue;
        }
        if (!type_util.is_core_wasm_scalar(field_ty)) return null;
        offset = align_up(offset, type_payload_alignment(field_ty));
        offset += type_payload_bytes(field_ty);
    }
    return offset;
}

/// True when a named struct carries managed payload (directly or nested) and lowers as ARC handle.
/// True when a named struct carries managed payload (directly or nested) and lowers as ARC handle.
pub fn struct_decl_has_managed_field(decl: StructDecl, structs: []const StructDecl) bool {
    for (decl.fields) |field| {
        if (type_util.is_managed_payload_type(field.ty)) return true;
        if (find_struct_decl(structs, field.ty)) |nested| {
            if (struct_decl_has_managed_field(nested, structs)) return true;
        }
    }
    return false;
}

/// Terminal pack leaf that is a managed object handle (text / [T] / managed struct).
/// Terminal pack leaf that is a managed object handle (text / [T] / managed struct).
pub fn pack_slot_width(ty: []const u8, structs: []const StructDecl) ?usize {
    if (is_tuple_type_name(ty)) return tuple_pack_width_with_structs(ty, structs);
    if (find_struct_decl(structs, ty)) |decl| {
        if (pure_scalar_struct_pack_width(decl, structs)) |w| return w;
        // Managed struct direct slot: one i32 ARC handle (never flatten fields into Tuple).
        if (struct_decl_has_managed_field(decl, structs)) return 4;
        return null;
    }
    if (type_util.is_tuple_packable_leaf_type(ty)) return type_payload_bytes(ty);
    return null;
}

/// Scheme A element width: scalar, managed handle, nested Tuple, pure-scalar struct sub-layout,
/// or managed-struct handle slot (never type-flatten).
/// Scheme A element width: scalar, managed handle, nested Tuple, pure-scalar struct sub-layout,
/// or managed-struct handle slot (never type-flatten).
pub fn tuple_pack_width_with_structs(tuple_ty: []const u8, structs: []const StructDecl) ?usize {
    if (!is_tuple_type_name(tuple_ty)) return null;
    const arity = tuple_arity(tuple_ty) orelse return null;
    var total: usize = 0;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return null;
        total += pack_slot_width(elem_ty, structs) orelse return null;
    }
    return total;
}

pub fn append_tuple_leaf_types_with_structs(
    allocator: std.mem.Allocator,
    ty: []const u8,
    structs: []const StructDecl,
    out: *std.ArrayList([]const u8),
) CodegenError!void {
    if (is_tuple_type_name(ty)) {
        const arity = tuple_arity(ty) orelse return error.UnsupportedLowering;
        var idx: usize = 0;
        while (idx < arity) : (idx += 1) {
            const elem_ty = tuple_element_type_at(ty, idx) orelse return error.UnsupportedLowering;
            try append_tuple_leaf_types_with_structs(allocator, elem_ty, structs, out);
        }
        return;
    }
    if (find_struct_decl(structs, ty)) |decl| {
        if (struct_decl_has_managed_field(decl, structs)) {
            // Managed struct: single ARC handle leaf; do not expand fields into the pack.
            try out.append(allocator, ty);
            return;
        }
        if (pure_scalar_struct_pack_width(decl, structs) == null) return error.UnsupportedTupleStorageLeaf;
        for (decl.fields) |field| {
            try append_tuple_leaf_types_with_structs(allocator, field.ty, structs, out);
        }
        return;
    }
    if (!type_util.is_tuple_packable_leaf_type(ty)) return error.UnsupportedTupleStorageLeaf;
    try out.append(allocator, ty);
}

/// Scheme A: packed Tuple storage layout (scalar + managed + struct nested slots).
/// Scheme A: packed Tuple storage layout (scalar + managed + struct nested slots).
pub fn append_tuple_leaf_types(
    allocator: std.mem.Allocator,
    tuple_ty: []const u8,
    out: *std.ArrayList([]const u8),
) CodegenError!void {
    // Malformed Tuple type names are a lowering invariant failure, not overload miss.
    type_util.append_tuple_leaf_types(allocator, tuple_ty, out) catch return error.UnsupportedLowering;
}

// pack leaf helpers (shared with storage layout collect)

pub fn parse_inline_union_layout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    if (!has_top_level_token(tokens, start_idx, end_idx, "|")) return null;

    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);

    var next_non_nil_tag: usize = 1;
    var branch_start = start_idx;
    while (branch_start < end_idx) {
        if (tok_eq(tokens[branch_start], "|")) {
            branch_start += 1;
            continue;
        }

        const branch_end = find_top_level_token(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start) return null;
        const payload_start = payload_tys.items.len;

        if (branch_end == branch_start + 1 and tok_eq(tokens[branch_start], "nil")) {
            try branches.append(allocator, .{
                .ty = "nil",
                .tag = 0,
                .payload_start = payload_start,
                .payload_len = 0,
            });
        } else {
            const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, branch_start, branch_end, owned_types)) orelse return null;
            if (parsed_ty.next_idx != branch_end) return null;
            try append_union_branch_payload_types(allocator, tokens, parsed_ty.ty, structs, struct_layouts, &payload_tys);
            try branches.append(allocator, .{
                .ty = parsed_ty.ty,
                .tag = next_non_nil_tag,
                .payload_start = payload_start,
                .payload_len = payload_tys.items.len - payload_start,
            });
            next_non_nil_tag += 1;
        }

        branch_start = branch_end;
        if (branch_start < end_idx and tok_eq(tokens[branch_start], "|")) branch_start += 1;
    }

    if (branches.items.len < 2) return null;
    const source_ty = try compact_token_text(allocator, tokens, start_idx, end_idx);
    errdefer allocator.free(source_ty);
    try owned_types.append(allocator, source_ty);

    return .{
        .source_ty = source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}
