//! WASI host call / result emit (no host table parse; see codegen_wasi_registry.zig).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_ownership = @import("codegen_ownership.zig");

const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const find_line_start = codegen_tokens.find_line_start;
const is_line_start = codegen_tokens.is_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const public_decl_name = codegen_names.public_decl_name;
const append_fmt = codegen_names.append_fmt;
const string_literal_arg_lexeme = codegen_tokens.string_literal_arg_lexeme;
const Range = codegen_tokens.Range;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const WASI_FAMILY_TMP_LOCAL = constants.WASI_FAMILY_TMP_LOCAL;
const is_error_like_type = codegen_collect_util.is_error_like_type;
const module_tokens_equal = codegen_tokens.module_tokens_equal;

const LocalSet = context.LocalSet;
const Local = model.Local;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const StructDecl = model.StructDecl;
const StructField = model.StructField;
const StructLayout = model.StructLayout;
const StructLocal = model.StructLocal;
const UnionLocal = model.UnionLocal;
const FuncDecl = model.FuncDecl;
const HostImport = model.HostImport;
const find_local_type = context.find_local_type;
const find_storage_local = context.find_storage_local;
const find_struct_local = context.find_struct_local;
const find_union_local = context.find_union_local;
const storage_type_name_for_elem = context.storage_type_name_for_elem;

const find_union_branch_by_type = codegen_storage_layout.find_union_branch_by_type;
const error_enum_branch_value = codegen_storage_layout.error_enum_branch_value;
const find_storage_primitive_local = codegen_storage_layout.find_storage_primitive_local;
const codegen_wasm_type = codegen_storage_layout.codegen_wasm_type;
const is_storage_type_name = codegen_storage_layout.is_storage_type_name;
const storage_type_id_for_element = codegen_storage_layout.storage_type_id_for_element;
const is_tuple_type_name = codegen_storage_layout.is_tuple_type_name;
const struct_field_payload_offset = codegen_storage_layout.struct_field_payload_offset;
const append_load_for_payload_type = payload_wat.append_load_for_payload_type;
const emit_replace_managed_local_from_tmp = codegen_ownership.emit_replace_managed_local_from_tmp;
const emit_storage_len_ptr = storage_wat.emit_storage_len_ptr;
const emit_storage_data_ptr = storage_wat.emit_storage_data_ptr;

const UnionLayout = codegen_union_layout.UnionLayout;
const UnionBranch = codegen_union_layout.UnionBranch;
const union_layouts_equal = codegen_union_layout.union_layouts_equal;
const free_union_layout = codegen_union_layout.free_union_layout;
const clone_union_layout = codegen_union_layout.clone_union_layout;
const union_branch_is_status_i32 = codegen_union_layout.union_branch_is_status_i32;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const wasi_lowering = codegen_wasi_registry.wasi_lowering;
const append_wasi_import_symbol = codegen_wasi_registry.append_wasi_import_symbol;
const find_wasi_host_import = codegen_wasi_registry.find_wasi_host_import;
const find_wasi_host_import_by_source = codegen_wasi_registry.find_wasi_host_import_by_source;
const parse_wasi_link_at_args = codegen_wasi_registry.parse_wasi_link_at_args;
const wasi_coarse_failed_variant_name = codegen_wasi_registry.wasi_coarse_failed_variant_name;
const wasi_coarse_closed_variant_name = codegen_wasi_registry.wasi_coarse_closed_variant_name;
const wasi_coarse_error_always_failed = codegen_wasi_registry.wasi_coarse_error_always_failed;
const WASI_BINDING_ENTRY_SOURCE = codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE;

const find_wasi_host_import_for_tokens = codegen_imports.find_wasi_host_import_for_tokens;
const wasi_source_for_tokens = codegen_imports.wasi_source_for_tokens;
const find_root_module_index = codegen_imports.find_root_module_index;
const expr_call_head = codegen_imports.expr_call_head;
const call_head_at = codegen_imports.call_head_at;

fn emit_wasi_family_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!try emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, "i32", out)) {
        if (!try emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, "u8", out)) return false;
        try out.appendSlice(allocator, "    i32.extend8_u\n");
    }
    try append_fmt(allocator, out, "    local.set ${s}\n", .{WASI_FAMILY_TMP_LOCAL});

    // Accept both the public 4/6 family values and already-canonical 0/1 values.
    try append_fmt(allocator, out, "    local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 0\n    i32.eq\n    if (result i32)\n      i32.const 0\n    else\n");
    try append_fmt(allocator, out, "      local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "      i32.const 1\n      i32.eq\n      if (result i32)\n        i32.const 1\n      else\n");
    try append_fmt(allocator, out, "        local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "        i32.const 4\n        i32.eq\n        if (result i32)\n          i32.const 0\n        else\n");
    try append_fmt(allocator, out, "          local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 6\n          i32.eq\n          if (result i32)\n            i32.const 1\n          else\n            unreachable\n          end\n        end\n      end\n    end\n");
    return true;
}

const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;

/// Callback into codegen_pipeline emit_expr (breaks import cycle).
pub const EmitExprFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub fn emit_wasi_result_filesize_multi_assignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_filesize_error) return false;

    const first_lhs_end = find_arg_end(tokens, lhs_start_idx, eq_idx);
    if (first_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (first_lhs_end >= eq_idx or !tok_eq(tokens[first_lhs_end], ",")) return error.NoMatchingCall;
    const second_lhs_start = first_lhs_end + 1;
    const second_lhs_end = find_arg_end(tokens, second_lhs_start, eq_idx);
    if (second_lhs_end != second_lhs_start + 1 or second_lhs_end != eq_idx or tokens[second_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const written_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[second_lhs_start].lexeme;
    const written_ty = find_local_type(locals.locals.items, written_name) orelse return error.NoMatchingCall;
    const status_ty = find_local_type(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, written_ty, "u64")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emit_wasi_result_filesize_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emit_wasi_result_filesize_values(allocator, out);
    try append_fmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try append_fmt(allocator, out, "    local.set ${s}\n", .{written_name});
    return true;
}

pub fn emit_wasi_result_u64_stream_status_multi_assignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_u64_stream_error) return false;

    const first_lhs_end = find_arg_end(tokens, lhs_start_idx, eq_idx);
    if (first_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (first_lhs_end >= eq_idx or !tok_eq(tokens[first_lhs_end], ",")) return error.NoMatchingCall;
    const second_lhs_start = first_lhs_end + 1;
    const second_lhs_end = find_arg_end(tokens, second_lhs_start, eq_idx);
    if (second_lhs_end != second_lhs_start + 1 or second_lhs_end != eq_idx or tokens[second_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const value_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[second_lhs_start].lexeme;
    const value_ty = find_local_type(locals.locals.items, value_name) orelse return error.NoMatchingCall;
    const status_ty = find_local_type(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, value_ty, "u64")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emit_wasi_result_u64_stream_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emit_wasi_result_filesize_values(allocator, out);
    try append_fmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try append_fmt(allocator, out, "    local.set ${s}\n", .{value_name});
    return true;
}

pub fn emit_wasi_result_descriptor_status_multi_assignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_descriptor_error) return false;

    const first_lhs_end = find_arg_end(tokens, lhs_start_idx, eq_idx);
    if (first_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (first_lhs_end >= eq_idx or !tok_eq(tokens[first_lhs_end], ",")) return error.NoMatchingCall;
    const second_lhs_start = first_lhs_end + 1;
    const second_lhs_end = find_arg_end(tokens, second_lhs_start, eq_idx);
    if (second_lhs_end != second_lhs_start + 1 or second_lhs_end != eq_idx or tokens[second_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const descriptor_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[second_lhs_start].lexeme;
    const descriptor_ty = find_local_type(locals.locals.items, descriptor_name) orelse return error.NoMatchingCall;
    const status_ty = find_local_type(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, descriptor_ty, "i32")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emit_wasi_result_descriptor_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emit_wasi_result_descriptor_values(allocator, out);
    try append_fmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try append_fmt(allocator, out, "    local.set ${s}\n", .{descriptor_name});
    return true;
}

pub fn emit_wasi_result_unit_status_multi_assignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_unit_error) return false;

    const discard_lhs_end = find_arg_end(tokens, lhs_start_idx, eq_idx);
    if (discard_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (!std.mem.eql(u8, tokens[lhs_start_idx].lexeme, "_")) return error.NoMatchingCall;
    if (discard_lhs_end >= eq_idx or !tok_eq(tokens[discard_lhs_end], ",")) return error.NoMatchingCall;

    const status_lhs_start = discard_lhs_end + 1;
    const status_lhs_end = find_arg_end(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx or tokens[status_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const status_name = tokens[status_lhs_start].lexeme;
    const status_ty = find_local_type(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emit_wasi_result_unit_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emit_wasi_result_unit_status_value(allocator, out);
    try append_fmt(allocator, out, "    local.set ${s}\n", .{status_name});
    return true;
}

pub fn emit_wasi_result_read_multi_assignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_read_error) return false;

    const data_lhs_end = find_arg_end(tokens, lhs_start_idx, eq_idx);
    if (data_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (data_lhs_end >= eq_idx or !tok_eq(tokens[data_lhs_end], ",")) return error.NoMatchingCall;

    const done_lhs_start = data_lhs_end + 1;
    const done_lhs_end = find_arg_end(tokens, done_lhs_start, eq_idx);
    if (done_lhs_end != done_lhs_start + 1 or done_lhs_end >= eq_idx or tokens[done_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }
    if (!tok_eq(tokens[done_lhs_end], ",")) return error.NoMatchingCall;

    const status_lhs_start = done_lhs_end + 1;
    const status_lhs_end = find_arg_end(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx or tokens[status_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const data_name = tokens[lhs_start_idx].lexeme;
    const done_name = tokens[done_lhs_start].lexeme;
    const status_name = tokens[status_lhs_start].lexeme;
    const data_storage = find_storage_local(locals.storage_locals.items, data_name) orelse return error.NoMatchingCall;
    const done_ty = find_local_type(locals.locals.items, done_name) orelse return error.NoMatchingCall;
    const status_ty = find_local_type(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, data_storage.elem_ty, "u8")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, done_ty, "bool")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emit_wasi_result_read_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emit_wasi_result_read_values(allocator, out);
    try append_fmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try append_fmt(allocator, out, "    local.set ${s}\n", .{done_name});
    try append_fmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emit_replace_managed_local_from_tmp(allocator, data_name, out);
    return true;
}

pub fn emit_wasi_result_list_u8_status_multi_assignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_list_u8_error) return false;

    const data_lhs_end = find_arg_end(tokens, lhs_start_idx, eq_idx);
    if (data_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (data_lhs_end >= eq_idx or !tok_eq(tokens[data_lhs_end], ",")) return error.NoMatchingCall;

    const status_lhs_start = data_lhs_end + 1;
    const status_lhs_end = find_arg_end(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx or tokens[status_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const data_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[status_lhs_start].lexeme;
    const data_storage = find_storage_local(locals.storage_locals.items, data_name) orelse return error.NoMatchingCall;
    const status_ty = find_local_type(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, data_storage.elem_ty, "u8")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emit_wasi_result_list_u8_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emit_wasi_result_list_u8_values(allocator, out);
    try append_fmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try append_fmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emit_replace_managed_local_from_tmp(allocator, data_name, out);
    return true;
}

pub fn emit_wasi_record_struct_binding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trim_parens(tokens, eq_idx + 1, end_idx);
    const call_head = expr_call_head(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const import = find_wasi_host_import_for_tokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    if (!try emit_wasi_record_result_fields(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, import, decl.name, out)) {
        return false;
    }

    var i = decl.fields.len;
    while (i > 0) {
        i -= 1;
        try append_fmt(allocator, out, "    local.set ${s}.{s}\n", .{
            tokens[start_idx].lexeme,
            public_decl_name(decl.fields[i].name),
        });
    }
    return true;
}

pub fn emit_wasi_record_return_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const struct_name = result_struct orelse return false;
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const import = find_wasi_host_import_for_tokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    const decl = find_struct_decl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (decl.fields.len != result_tys.len) return error.NoMatchingCall;
    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return error.NoMatchingCall;
    }
    return try emit_wasi_record_result_fields(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, import, struct_name, out);
}

pub fn emit_wasi_record_result_fields(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    struct_name: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    _ = locals;
    _ = tokens;
    if (args_start != args_end) return error.NoMatchingCall;
    const lowering = wasi_lowering(import) orelse return false;
    const result_record = lowering.result_record orelse return false;
    if (!std.mem.eql(u8, result_record, struct_name)) return false;
    if (find_struct_layout(ctx.struct_layouts, struct_name) != null) return false;
    const decl = find_struct_decl(ctx.structs, struct_name) orelse return error.NoMatchingCall;

    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");

    for (decl.fields) |field| {
        const field_name = public_decl_name(field.name);
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return error.NoMatchingCall;
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        if (field_offset != 0) {
            try append_fmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
        }
        try append_load_for_payload_type(allocator, out, field.ty);
    }
    return true;
}

pub fn emit_bare_wasi_host_import_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const wasi_import = find_wasi_host_import_for_tokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    const lowering = wasi_lowering(wasi_import) orelse return false;
    if (!lowering.resource_drop and !lowering.result_unit_error and !lowering.result_filesize_error and !lowering.result_u64_stream_error) return false;
    return try emit_wasi_host_import_expr(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, true, out, emit_expr);
}

pub fn emit_wasi_host_import_expr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    allow_statement_result: bool,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (lowering.resource_drop) {
        if (!allow_statement_result) return false;
        return try emit_wasi_resource_drop_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_storage_elem) |elem_ty| {
        if (!std.mem.eql(u8, elem_ty, "u8")) return false;
        return try emit_wasi_list_u8_result_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_list_preopen) {
        return try emit_wasi_list_preopen_result_call(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (lowering.result_unit_error) {
        if (!allow_statement_result) return false;
        return try emit_wasi_result_unit_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_list_u8_error) return false;
    if (lowering.result_filesize_error) {
        if (!allow_statement_result) return false;
        return try emit_wasi_result_filesize_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_u64_stream_error) {
        if (!allow_statement_result) return false;
        return try emit_wasi_result_u64_stream_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_record != null) return false;
    if (lowering.result == null) return false;
    if (args_start != args_end) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_resource_drop_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const arg_end = find_arg_end(tokens, args_start, args_end);
    if (arg_end != args_end) return error.NoMatchingCall;
    // Bare i32 or resource shell (Dir/File) via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, arg_end, locals, ctx, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_list_u8_result_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "random/random/get-random-bytes")) return false;
    const arg_end = find_arg_end(tokens, args_start, args_end);
    if (arg_end == args_start or arg_end != args_end) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, args_start, arg_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    global.get $__wasi_result_area_base
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    call $__wasi_list_u8_to_storage
        \\
    );
    return true;
}

/// G6.1 / P3: () -> list<tuple<descriptor,string>> as do [Tuple<Dir,text>] (Dir.id i64 + text).
/// G6.1 / P3: () -> list<tuple<descriptor,string>> as do [Tuple<Dir,text>] (Dir.id i64 + text).
pub fn emit_wasi_list_preopen_result_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    _ = tokens;
    _ = locals;
    if (!std.mem.eql(u8, import.target, "filesystem/preopens/get-directories")) return false;
    if (args_start != args_end) return error.NoMatchingCall;
    // Prefer registered storage-pack layout for Tuple<Dir,text>; fall back is wrong for release.
    const pack_type_id = storage_type_id_for_element("Tuple<Dir,text>", ctx);
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    global.get $__wasi_result_area_base
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\
    );
    try append_fmt(allocator, out, "    i32.const {d}\n", .{pack_type_id});
    try out.appendSlice(allocator, "    call $__wasi_list_preopen_to_storage\n");
    return true;
}

pub fn emit_wasi_result_unit_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at")) {
        return try emit_wasi_result_link_at_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.create-directory-at") or
        std.mem.eql(u8, import.target, "filesystem/types/descriptor.remove-directory-at"))
    {
        return try emit_wasi_result_descriptor_path_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.write")) {
        return try emit_wasi_result_output_write_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    // G6.3: tcp/udp-socket.bind(socket, IpSocketAddress)
    if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.bind") or
        std.mem.eql(u8, import.target, "sockets/types/udp-socket.bind"))
    {
        return try emit_wasi_result_socket_bind_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.sync") and
        !std.mem.eql(u8, import.target, "io/streams/output-stream.flush"))
    {
        return false;
    }
    const arg_end = find_arg_end(tokens, args_start, args_end);
    if (arg_end == args_start or arg_end != args_end) return error.NoMatchingCall;
    // Bare i32 or File/OutputStream resource shell via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, arg_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

/// Scratch offset past result-area header for packing `ip-socket-address` (G6.3).
const SOCKET_ADDR_PACK_OFF: u32 = 64;

/// Lower tcp/udp-socket.bind: handle + pack IpSocketAddress (payload enum) + unit result area.
pub fn emit_wasi_result_socket_bind_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "sockets/types/tcp-socket.bind") and
        !std.mem.eql(u8, import.target, "sockets/types/udp-socket.bind"))
        return false;

    const socket_end = find_arg_end(tokens, args_start, args_end);
    if (socket_end == args_start or socket_end >= args_end or !tok_eq(tokens[socket_end], ",")) return error.NoMatchingCall;
    const addr_start = socket_end + 1;
    const addr_end = find_arg_end(tokens, addr_start, args_end);
    if (addr_end == addr_start or addr_end != args_end) return error.NoMatchingCall;

    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, socket_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_wasi_pack_ip_socket_address_arg(allocator, tokens, addr_start, addr_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

/// Pack IpSocketAddress (payload enum V4|V6 or ctor) into scratch; leave ptr on stack.
fn emit_wasi_pack_ip_socket_address_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    _ = ctx;
    _ = emit_expr; // pack uses struct/union locals only in v1
    const range = trim_parens(tokens, start_idx, end_idx);

    // Local payload-enum: name with __union_tag / __union_payload_*
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const uname = tokens[range.start].lexeme;
        if (find_union_local(locals.union_locals.items, uname) != null) {
            return try emit_wasi_pack_ip_socket_address_from_union_local(allocator, uname, out);
        }
    }

    // Ctor V4(expr) / V6(expr)
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const case_name = public_decl_name(tokens[call_head.name_idx].lexeme);
    const is_v4 = std.mem.eql(u8, case_name, "V4");
    const is_v6 = std.mem.eql(u8, case_name, "V6");
    if (!is_v4 and !is_v6) return false;

    // Payload must be unmanaged struct local for v1 pack.
    const payload_range = trim_parens(tokens, call_head.args_start, call_head.args_end);
    if (payload_range.end != payload_range.start + 1 or tokens[payload_range.start].kind != .ident) return false;
    const sname = tokens[payload_range.start].lexeme;
    const struct_local = find_struct_local(locals.struct_locals.items, sname) orelse return false;

    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    // ptr stays on stack for store sequence via local tee pattern: duplicate with local? Use get/set base each time.
    // Store disc
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    if (is_v4) {
        try out.appendSlice(allocator, "    i32.const 0\n"); // ipv4 disc
        try out.appendSlice(allocator, "    i32.store\n");
        // port u16 @ +4
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
        try out.appendSlice(allocator, "    i32.add\n");
        try append_fmt(allocator, out, "    local.get ${s}.port\n", .{struct_local.name});
        try out.appendSlice(allocator, "    i32.store16\n");
        // pad u16 @ +6, then a,b,c,d @ +8..+11
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 6});
        try out.appendSlice(allocator, "    i32.add\n    i32.const 0\n    i32.store16\n");
        inline for (.{ "a", "b", "c", "d" }, 0..) |field, fi| {
            try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
            try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8 + fi});
            try out.appendSlice(allocator, "    i32.add\n");
            try append_fmt(allocator, out, "    local.get ${s}.{s}\n", .{ struct_local.name, field });
            try out.appendSlice(allocator, "    i32.store8\n");
        }
    } else {
        try out.appendSlice(allocator, "    i32.const 1\n"); // ipv6 disc
        try out.appendSlice(allocator, "    i32.store\n");
        // port @ +4
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
        try out.appendSlice(allocator, "    i32.add\n");
        try append_fmt(allocator, out, "    local.get ${s}.port\n", .{struct_local.name});
        try out.appendSlice(allocator, "    i32.store16\n");
        // flowinfo = 0 @ +8
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8});
        try out.appendSlice(allocator, "    i32.add\n");
        try out.appendSlice(allocator, "    i32.const 0\n");
        try out.appendSlice(allocator, "    i32.store\n");
        // addr[16] from hi||lo in network byte order @ +12.
        try append_store_u64_big_endian_field(allocator, out, struct_local.name, "hi", SOCKET_ADDR_PACK_OFF + 12, "    ");
        try append_store_u64_big_endian_field(allocator, out, struct_local.name, "lo", SOCKET_ADDR_PACK_OFF + 20, "    ");
        // scope_id = 0 @ +28
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 28});
        try out.appendSlice(allocator, "    i32.add\n");
        try out.appendSlice(allocator, "    i32.const 0\n");
        try out.appendSlice(allocator, "    i32.store\n");
    }
    // leave pack ptr on stack
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    return true;
}

fn emit_wasi_pack_ip_socket_address_from_union_local(
    allocator: std.mem.Allocator,
    uname: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    // Tag 0 = V4, 1 = V6. Payloads: V4 a,b,c,d,port; V6 hi,lo,port (max slots overlap).
    // For v1, only support packing when tag known at emit is too hard; always emit branch on tag.
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    try append_fmt(allocator, out, "    local.get ${s}.__union_tag\n", .{uname});
    try out.appendSlice(allocator, "    i32.store\n"); // disc = case tag (0=V4, 1=V6)

    // Common: port is last payload field for both — V4 has 5 slots (0..4), V6 has 3 (0..2).
    // Layout for V4: p0=a p1=b p2=c p3=d p4=port
    // Layout for V6: p0=hi p1=lo p2=port — different; branch on tag.
    try append_fmt(allocator, out, "    local.get ${s}.__union_tag\n", .{uname});
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if\n");
    // V4 pack: port @+4, padding @+6, bytes @+8..+11.
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
    try out.appendSlice(allocator, "      i32.add\n");
    try append_fmt(allocator, out, "      local.get ${s}.__union_payload_4\n", .{uname});
    try out.appendSlice(allocator, "      i32.store16\n");
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 6});
    try out.appendSlice(allocator, "      i32.add\n      i32.const 0\n      i32.store16\n");
    inline for (0..4) |fi| {
        try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
        try append_fmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8 + fi});
        try out.appendSlice(allocator, "      i32.add\n");
        try append_fmt(allocator, out, "      local.get ${s}.__union_payload_{d}\n", .{ uname, fi });
        try out.appendSlice(allocator, "      i32.store8\n");
    }
    try out.appendSlice(allocator, "    else\n");
    // V6 pack
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
    try out.appendSlice(allocator, "      i32.add\n");
    try append_fmt(allocator, out, "      local.get ${s}.__union_payload_2\n", .{uname});
    try out.appendSlice(allocator, "      i32.store16\n");
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8});
    try out.appendSlice(allocator, "      i32.add\n");
    try out.appendSlice(allocator, "      i32.const 0\n");
    try out.appendSlice(allocator, "      i32.store\n");
    try append_store_u64_big_endian_field(allocator, out, uname, "__union_payload_0", SOCKET_ADDR_PACK_OFF + 12, "      ");
    try append_store_u64_big_endian_field(allocator, out, uname, "__union_payload_1", SOCKET_ADDR_PACK_OFF + 20, "      ");
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 28});
    try out.appendSlice(allocator, "      i32.add\n");
    try out.appendSlice(allocator, "      i32.const 0\n");
    try out.appendSlice(allocator, "      i32.store\n");
    try out.appendSlice(allocator, "    end\n");

    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    return true;
}

fn append_store_u64_big_endian_field(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_base: []const u8,
    field_name: []const u8,
    offset: u32,
    indent: []const u8,
) !void {
    inline for (0..8) |byte_idx| {
        const shift: u32 = @as(u32, 56 - byte_idx * 8);
        try append_fmt(allocator, out, "{s}global.get $__wasi_result_area_base\n", .{indent});
        try append_fmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset + byte_idx });
        try append_fmt(allocator, out, "{s}i32.add\n", .{indent});
        try append_fmt(allocator, out, "{s}local.get ${s}.{s}\n", .{ indent, local_base, field_name });
        try append_fmt(allocator, out, "{s}i64.const {d}\n", .{ indent, shift });
        try append_fmt(allocator, out, "{s}i64.shr_u\n", .{indent});
        try append_fmt(allocator, out, "{s}i64.const 255\n{s}i64.and\n{s}i64.store8\n", .{ indent, indent, indent });
    }
}

pub fn emit_wasi_result_descriptor_path_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.create-directory-at") and
        !std.mem.eql(u8, import.target, "filesystem/types/descriptor.remove-directory-at"))
    {
        return false;
    }

    const descriptor_end = find_arg_end(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tok_eq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const path_start = descriptor_end + 1;
    const path_end = find_arg_end(tokens, path_start, args_end);
    if (path_end == path_start or path_end != args_end) return error.NoMatchingCall;

    // Bare i32 or Dir resource shell via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_wasi_string_arg(allocator, tokens, path_start, path_end, locals, ctx, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_result_output_write_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/output-stream.write")) return false;

    const stream_end = find_arg_end(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end >= args_end or !tok_eq(tokens[stream_end], ",")) return error.NoMatchingCall;
    const data_start = stream_end + 1;
    const data_end = find_arg_end(tokens, data_start, args_end);
    if (data_end == data_start or data_end != args_end) return error.NoMatchingCall;

    // Bare i32 or OutputStream resource shell via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, stream_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_wasi_list_u8_arg(allocator, tokens, data_start, data_end, locals, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_result_descriptor_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    // G6.3: tcp/udp-socket.create(family) -> result<socket, error-code>
    if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.create") or
        std.mem.eql(u8, import.target, "sockets/types/udp-socket.create"))
    {
        const family_end = find_arg_end(tokens, args_start, args_end);
        if (family_end == args_start or family_end != args_end) return error.NoMatchingCall;
        if (!try emit_wasi_family_arg(allocator, tokens, args_start, family_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try out.appendSlice(allocator, "    call $");
        try append_wasi_import_symbol(allocator, out, import.target);
        try out.appendSlice(allocator, "\n");
        return true;
    }

    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.open-at")) return false;

    const descriptor_end = find_arg_end(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tok_eq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const path_flags_start = descriptor_end + 1;
    const path_flags_end = find_arg_end(tokens, path_flags_start, args_end);
    if (path_flags_end == path_flags_start or path_flags_end >= args_end or !tok_eq(tokens[path_flags_end], ",")) return error.NoMatchingCall;
    const path_start = path_flags_end + 1;
    const path_end = find_arg_end(tokens, path_start, args_end);
    if (path_end == path_start or path_end >= args_end or !tok_eq(tokens[path_end], ",")) return error.NoMatchingCall;
    const open_flags_start = path_end + 1;
    const open_flags_end = find_arg_end(tokens, open_flags_start, args_end);
    if (open_flags_end == open_flags_start or open_flags_end >= args_end or !tok_eq(tokens[open_flags_end], ",")) return error.NoMatchingCall;
    const descriptor_flags_start = open_flags_end + 1;
    const descriptor_flags_end = find_arg_end(tokens, descriptor_flags_start, args_end);
    if (descriptor_flags_end == descriptor_flags_start or descriptor_flags_end != args_end) return error.NoMatchingCall;

    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, path_flags_start, path_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emit_wasi_string_arg(allocator, tokens, path_start, path_end, locals, ctx, out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, open_flags_start, open_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, descriptor_flags_start, descriptor_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

/// Lower descriptor/resource handle arg: bare i32, or unmanaged resource struct `.id` (i64 → i32).
/// Lower descriptor/resource handle arg: bare i32, or unmanaged resource struct `.id` (i64 → i32).
pub fn emit_wasi_descriptor_handle_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (try emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, "i32", out)) return true;

    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    const struct_local = find_struct_local(locals.struct_locals.items, tokens[range.start].lexeme) orelse return false;
    if (find_struct_layout(ctx.struct_layouts, struct_local.ty) != null) return false;
    const decl = find_struct_decl(ctx.structs, struct_local.ty) orelse return false;
    var id_ty: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, public_decl_name(field.name), "id")) {
            id_ty = field.ty;
            break;
        }
    }
    const field_ty = id_ty orelse return false;
    try append_fmt(allocator, out, "    local.get ${s}.id\n", .{struct_local.name});
    if (std.mem.eql(u8, field_ty, "i64")) {
        try out.appendSlice(allocator, "    i32.wrap_i64\n");
        return true;
    }
    if (std.mem.eql(u8, field_ty, "i32")) return true;
    return false;
}

pub fn emit_wasi_result_link_at_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at")) return false;
    const args = parse_wasi_link_at_args(tokens, args_start, args_end) orelse return error.NoMatchingCall;

    // Bare i32 or File resource shells via `.id` for both descriptor args.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args.descriptor_start, args.descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, args.old_flags_start, args.old_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emit_wasi_string_arg(allocator, tokens, args.old_path_start, args.old_path_end, locals, ctx, out)) return error.NoMatchingCall;
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args.new_descriptor_start, args.new_descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_wasi_string_arg(allocator, tokens, args.new_path_start, args.new_path_end, locals, ctx, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_string_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (string_literal_arg_lexeme(tokens, start_idx, end_idx)) |lexeme| {
        const data = ctx.string_data.find(lexeme) orelse return error.NoMatchingCall;
        try append_fmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
        try append_fmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
        return true;
    }

    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return false;
    if (tokens[range.start].kind != .ident) return false;
    const local_ty = find_local_type(locals.locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, local_ty, "text")) return false;
    const storage = find_storage_local(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emit_storage_data_ptr(allocator, out, tokens[range.start].lexeme);
    try emit_storage_len_ptr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

pub fn emit_wasi_result_filesize_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.write")) return false;

    const descriptor_end = find_arg_end(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tok_eq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const buffer_start = descriptor_end + 1;
    const buffer_end = find_arg_end(tokens, buffer_start, args_end);
    if (buffer_end == buffer_start or buffer_end >= args_end or !tok_eq(tokens[buffer_end], ",")) return error.NoMatchingCall;
    const offset_start = buffer_end + 1;
    const offset_end = find_arg_end(tokens, offset_start, args_end);
    if (offset_end == offset_start or offset_end != args_end) return error.NoMatchingCall;

    // Bare i32 or File resource shell via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_wasi_list_u8_arg(allocator, tokens, buffer_start, buffer_end, locals, out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, offset_start, offset_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_result_u64_stream_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/output-stream.check-write")) return false;

    const stream_end = find_arg_end(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end != args_end) return error.NoMatchingCall;

    // Bare i32 or OutputStream resource shell via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, stream_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_result_read_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.read")) return false;

    const descriptor_end = find_arg_end(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tok_eq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const length_start = descriptor_end + 1;
    const length_end = find_arg_end(tokens, length_start, args_end);
    if (length_end == length_start or length_end >= args_end or !tok_eq(tokens[length_end], ",")) return error.NoMatchingCall;
    const offset_start = length_end + 1;
    const offset_end = find_arg_end(tokens, offset_start, args_end);
    if (offset_end == offset_start or offset_end != args_end) return error.NoMatchingCall;

    // Bare i32 or File resource shell via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, length_start, length_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, offset_start, offset_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_result_list_u8_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/input-stream.read")) return false;

    const stream_end = find_arg_end(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end >= args_end or !tok_eq(tokens[stream_end], ",")) return error.NoMatchingCall;
    const len_start = stream_end + 1;
    const len_end = find_arg_end(tokens, len_start, args_end);
    if (len_end == len_start or len_end != args_end) return error.NoMatchingCall;

    // Bare i32 or InputStream resource shell via `.id`.
    if (!try emit_wasi_descriptor_handle_arg(allocator, tokens, args_start, stream_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, len_start, len_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try append_wasi_import_symbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

pub fn emit_wasi_result_unit_status_value(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

/// Emit error-enum payload for WASI err arm: open → always *Failed; unit/write → status 1 (*Closed) else *Failed.
/// Loads error-code from result-area offset `code_offset` (open-at/unit = 4; filesize write = 8).
/// Emit error-enum payload for WASI err arm: open → always *Failed; unit/write → status 1 (*Closed) else *Failed.
/// Loads error-code from result-area offset `code_offset` (open-at/unit = 4; filesize write = 8).
pub fn emit_wasi_coarse_error_enum_payload(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    import: WasiHostImport,
    err_ty: []const u8,
    code_offset: u32,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const failed_name = wasi_coarse_failed_variant_name(import, err_ty) orelse return false;
    const failed_val = error_enum_branch_value(tokens, err_ty, failed_name) orelse return false;
    if (wasi_coarse_error_always_failed(import)) {
        try append_fmt(allocator, out, "      i32.const {d}\n", .{failed_val});
        return true;
    }
    const closed_name = wasi_coarse_closed_variant_name(err_ty) orelse return false;
    const closed_val = error_enum_branch_value(tokens, err_ty, closed_name) orelse return false;
    // status = error-code+1; 1 ⇒ Closed (same as *status_to_error helpers).
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try append_fmt(allocator, out, "      i32.const {d}\n", .{code_offset});
    try out.appendSlice(allocator,
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\      i32.const 1
        \\      i32.eq
        \\      if (result i32)
        \\
    );
    try append_fmt(allocator, out, "        i32.const {d}\n", .{closed_val});
    try out.appendSlice(allocator, "      else\n");
    try append_fmt(allocator, out, "        i32.const {d}\n", .{failed_val});
    try out.appendSlice(allocator, "      end\n");
    return true;
}

pub fn union_branch_is_coarse_error(tokens: []const lexer.Token, layout: UnionLayout, branch: UnionBranch) bool {
    if (!is_error_like_type(tokens, branch.ty)) return false;
    if (branch.payload_len != 1) return false;
    if (branch.payload_start >= layout.payload_tys.len) return false;
    return is_error_like_type(tokens, layout.payload_tys[branch.payload_start]);
}

/// Lower unit fallible WASI host into exclusive union stack values: payload slots + tag.
/// Shapes: `nil | i32` (status), or `nil | DirError` / `DirError | nil` / FileError variants (coarse).
/// Lower unit fallible WASI host into exclusive union stack values: payload slots + tag.
/// Shapes: `nil | i32` (status), or `nil | DirError` / `DirError | nil` / FileError variants (coarse).
pub fn emit_wasi_unit_result_as_union_value(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_unit_error) return false;

    const nil_branch = find_union_branch_by_type(layout, "nil") orelse return false;
    if (nil_branch.tag != 0) return false;

    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (err_branch != null) return false;
        if (union_branch_is_status_i32(layout, branch)) {
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (union_branch_is_coarse_error(tokens, layout, branch)) {
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        return false;
    }
    const err = err_branch orelse return false;
    // Single i32/error payload slot only for this phase.
    if (layout.payload_tys.len != 1) return false;

    if (!try emit_wasi_result_unit_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: i32 payload, i32 tag (matches emitUnionValue order).
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      i32.const 0
        \\      i32.const 0
        \\    else
        \\
    );
    if (err_is_coarse) {
        if (!try emit_wasi_coarse_error_enum_payload(allocator, tokens, import, err.ty, 4, out)) {
            return error.NoMatchingCall;
        }
    } else {
        try out.appendSlice(allocator,
            \\      global.get $__wasi_result_area_base
            \\      i32.const 4
            \\      i32.add
            \\      i32.load
            \\      i32.const 1
            \\      i32.add
            \\
        );
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<filesize,error-code>` / stream check-write into exclusive union: e.g. `u64 | i32` or `u64 | FileError`.
/// Ok arm is written filesize/allowed (u64); err arm is status i32 or coarse FileError.
/// Lower `result<filesize,error-code>` / stream check-write into exclusive union: e.g. `u64 | i32` or `u64 | FileError`.
/// Ok arm is written filesize/allowed (u64); err arm is status i32 or coarse FileError.
pub fn emit_wasi_filesize_result_as_union_value(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    // Same result-area layout for write filesize and stream check-write u64.
    if (!lowering.result_filesize_error and !lowering.result_u64_stream_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (union_branch_is_status_i32(layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (union_branch_is_coarse_error(tokens, layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        // Ok arm: scalar filesize (u64).
        if (std.mem.eql(u8, branch.ty, "u64") and branch.payload_len == 1 and
            branch.payload_start < layout.payload_tys.len and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start], "u64"))
        {
            if (ok_branch != null) return false;
            ok_branch = branch;
            continue;
        }
        return false;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    if (layout.payload_tys.len != 2) return false;

    if (lowering.result_filesize_error) {
        if (!try emit_wasi_result_filesize_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
            return error.NoMatchingCall;
        }
    } else if (!try emit_wasi_result_u64_stream_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / emit_wasi_result_filesize_values).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try append_fmt(allocator, out, " {s}", .{codegen_wasm_type(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: filesize at result-area +8; zero err slot; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i64.load
                \\
            );
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: zero ok slot; status or coarse FileError at +8; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == err.payload_start and err_is_coarse) {
            if (!try emit_wasi_coarse_error_enum_payload(allocator, tokens, import, err.ty, 8, out)) {
                return error.NoMatchingCall;
            }
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i32.load
                \\      i32.const 1
                \\      i32.add
                \\
            );
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<tuple<list<u8>,bool>,error-code>` into exclusive union: e.g. `Tuple<[u8], bool> | i32`.
/// Ok arm is flattened tuple leaves (storage handle + bool); err arm is status i32 (error-code+1).
/// Lower `result<tuple<list<u8>,bool>,error-code>` into exclusive union: e.g. `Tuple<[u8], bool> | i32`.
/// Ok arm is flattened tuple leaves (storage handle + bool); err arm is status i32 (error-code+1).
pub fn emit_wasi_read_result_as_union_value(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_read_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    for (layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "i32") and branch.payload_len == 1 and
            branch.payload_start < layout.payload_tys.len and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start], "i32"))
        {
            if (err_branch != null) return false;
            err_branch = branch;
            continue;
        }
        // Ok arm: Tuple<[u8], bool> → two leaf slots.
        if (is_tuple_type_name(branch.ty) and branch.payload_len == 2 and
            branch.payload_start + 1 < layout.payload_tys.len and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start], "[u8]") and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start + 1], "bool"))
        {
            if (ok_branch != null) return false;
            ok_branch = branch;
            continue;
        }
        return false;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    if (layout.payload_tys.len != 3) return false;
    if (!std.mem.eql(u8, ok.ty, "Tuple<[u8],bool>") and !std.mem.eql(u8, ok.ty, "Tuple<[u8], bool>")) {
        // Compact source_ty from tokens drops spaces; branch.ty is compact.
        // Accept only the two-leaf shape already checked above.
        if (!(is_tuple_type_name(ok.ty) and
            std.mem.eql(u8, layout.payload_tys[ok.payload_start], "[u8]") and
            std.mem.eql(u8, layout.payload_tys[ok.payload_start + 1], "bool")))
        {
            return false;
        }
    }

    if (!try emit_wasi_result_read_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / multi-lhs data,done,status order).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try append_fmt(allocator, out, " {s}", .{codegen_wasm_type(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: list→storage + done bool; zero err slot; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i32.load
                \\      call $__wasi_list_u8_to_storage
                \\
            );
        } else if (idx == ok.payload_start + 1) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 12
                \\      i32.add
                \\      i32.load8_u
                \\
            );
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: empty storage + false done in ok slots; status = error-code + 1 at +4; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try storage_wat.emit_empty_storage_u8_value(allocator, out);
        } else if (idx == ok.payload_start + 1) {
            try out.appendSlice(allocator, "      i32.const 0\n");
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      i32.const 1
                \\      i32.add
                \\
            );
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<list<u8>,stream-error>` into exclusive union stack: e.g. `[u8] | i32` or `[u8] | StreamError`.
/// Ok arm is storage handle from list{ptr,len}; err arm is status i32 or coarse StreamError.
/// Lower `result<list<u8>,stream-error>` into exclusive union stack: e.g. `[u8] | i32` or `[u8] | StreamError`.
/// Ok arm is storage handle from list{ptr,len}; err arm is status i32 or coarse StreamError.
pub fn emit_wasi_list_u8_result_as_union_value(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_list_u8_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (union_branch_is_status_i32(layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (union_branch_is_coarse_error(tokens, layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        // Ok arm: managed list storage ([u8] handle as i32).
        if (is_storage_type_name(branch.ty) and branch.payload_len == 1 and
            branch.payload_start < layout.payload_tys.len and
            is_storage_type_name(layout.payload_tys[branch.payload_start]))
        {
            if (ok_branch != null) return false;
            ok_branch = branch;
            continue;
        }
        return false;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    if (layout.payload_tys.len != 2) return false;
    // Stream-read list is u8-only for this phase.
    if (!std.mem.eql(u8, ok.ty, "[u8]")) return false;
    if (!std.mem.eql(u8, layout.payload_tys[ok.payload_start], "[u8]")) return false;

    if (!try emit_wasi_result_list_u8_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / multi-lhs list+status order).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try append_fmt(allocator, out, " {s}", .{codegen_wasm_type(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: storage handle from list{ptr,len}; zero err slot; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i32.load
                \\      call $__wasi_list_u8_to_storage
                \\
            );
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: empty storage in ok slot; status or coarse StreamError at +4; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try storage_wat.emit_empty_storage_u8_value(allocator, out);
        } else if (idx == err.payload_start and err_is_coarse) {
            if (!try emit_wasi_coarse_error_enum_payload(allocator, tokens, import, err.ty, 4, out)) {
                return false;
            }
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      i32.const 1
                \\      i32.add
                \\
            );
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<descriptor,error-code>` into exclusive union stack: e.g. `Dir | i32` or `Dir | DirError`.
/// Ok arm carries resource payload (Dir.id as i64 from descriptor); err arm is status i32 or coarse error enum.
/// Lower `result<descriptor,error-code>` into exclusive union stack: e.g. `Dir | i32` or `Dir | DirError`.
/// Ok arm carries resource payload (Dir.id as i64 from descriptor); err arm is status i32 or coarse error enum.
pub fn emit_wasi_descriptor_result_as_union_value(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasi_lowering(import) orelse return false;
    if (!lowering.result_descriptor_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (union_branch_is_status_i32(layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (union_branch_is_coarse_error(tokens, layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        if (ok_branch != null) return false;
        if (branch.payload_len == 0) return false;
        ok_branch = branch;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    // Ok payload must be a single scalar slot (Dir → i64 id, or bare i32 descriptor sugar).
    if (ok.payload_len != 1) return false;
    if (ok.payload_start >= layout.payload_tys.len) return false;
    const ok_payload_ty = layout.payload_tys[ok.payload_start];
    if (!std.mem.eql(u8, ok_payload_ty, "i32") and !std.mem.eql(u8, ok_payload_ty, "i64")) return false;

    if (!try emit_wasi_result_descriptor_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / emitUnionBranchValue order).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try append_fmt(allocator, out, " {s}", .{codegen_wasm_type(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: fill ok payload from descriptor; zero other slots; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\
            );
            if (std.mem.eql(u8, payload_ty, "i64")) {
                try out.appendSlice(allocator, "      i64.extend_i32_s\n");
            }
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: zero ok slots; status or coarse *OpenFailed; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == err.payload_start and err_is_coarse) {
            if (!try emit_wasi_coarse_error_enum_payload(allocator, tokens, import, err.ty, 4, out)) {
                return error.NoMatchingCall;
            }
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      i32.const 1
                \\      i32.add
                \\
            );
        } else {
            try append_fmt(allocator, out, "      {s}.const 0\n", .{codegen_wasm_type(ctx, payload_ty)});
        }
    }
    try append_fmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn emit_wasi_result_read_values(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      global.get $__wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $__wasi_list_u8_to_storage
        \\      global.get $__wasi_result_area_base
        \\      i32.const 12
        \\      i32.add
        \\      i32.load8_u
        \\      i32.const 0
        \\    else
    );
    try storage_wat.emit_empty_storage_u8_value(allocator, out);
    try out.appendSlice(allocator,
        \\      i32.const 0
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

pub fn emit_wasi_result_list_u8_values(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      global.get $__wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $__wasi_list_u8_to_storage
        \\      i32.const 0
        \\    else
    );
    try storage_wat.emit_empty_storage_u8_value(allocator, out);
    try out.appendSlice(allocator,
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

pub fn emit_wasi_result_descriptor_values(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 0
        \\    else
        \\      i32.const 0
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

pub fn emit_wasi_result_filesize_values(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i64 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i64.load
        \\      i32.const 0
        \\    else
        \\      i64.const 0
        \\      global.get $__wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

pub fn emit_wasi_list_u8_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    out: *std.ArrayList(u8),
) !bool {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return false;
    if (tokens[range.start].kind != .ident) return false;
    const storage = find_storage_primitive_local(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emit_storage_data_ptr(allocator, out, tokens[range.start].lexeme);
    try emit_storage_len_ptr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}
