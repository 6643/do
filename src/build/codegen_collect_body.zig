//! Body-local / loop / multi-result local collection for codegen emit.
const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_emit_storage_values = @import("codegen_emit_storage_values.zig");
const codegen_emit_storage_operations = @import("codegen_emit_storage_operations.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_emit_struct = @import("codegen_emit_struct.zig");
const codegen_emit_struct_fields = @import("codegen_emit_struct_fields.zig");
const codegen_emit_union = @import("codegen_emit_union.zig");
const codegen_emit_control = @import("codegen_emit_control.zig");
const codegen_ownership = @import("codegen_ownership.zig");
const codegen_host_imports = @import("codegen_host_imports.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");

const append_loop_source_storage_local = context.append_loop_source_storage_local;
const parse_union_type_layout = codegen_collect_util.parse_union_type_layout;
const InferredUnionBinding = model.InferredUnionBinding;
const find_union_local_exact = context.find_union_local_exact;
const MultiResultLhs = model.MultiResultLhs;
const SourceOrigin = model.SourceOrigin;
const find_payload_enum_decl = codegen_imports.find_payload_enum_decl;
const tok_eq = codegen_tokens.tok_eq;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const publicDeclName = codegen_names.public_decl_name;
const append_fmt = codegen_names.append_fmt;
const findTopLevelBlockOpen = codegen_tokens.find_top_level_block_open;
const find_stmt_end = codegen_tokens.find_stmt_end;
const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const StructLocal = model.StructLocal;
const StorageLocal = model.StorageLocal;
const FuncDecl = model.FuncDecl;
const FuncResultItem = model.FuncResultItem;
const StructDecl = model.StructDecl;
const FieldReflectionLoopHeader = context.FieldReflectionLoopHeader;
const CallbackBinding = model.CallbackBinding;
const CallbackCallArg = model.CallbackCallArg;
const ExprCallHead = model.ExprCallHead;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const find_local_type = context.find_local_type;
const find_storage_local = context.find_storage_local;
const find_struct_local = context.find_struct_local;
const find_union_local = context.find_union_local;
const has_local = context.has_local;
const UnionLayout = codegen_union_layout.UnionLayout;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const cloneUnionLayout = codegen_union_layout.clone_union_layout;
const unionLayoutsEqual = codegen_union_layout.union_layouts_equal;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const pure_scalar_struct_pack_width = codegen_collect_util.pure_scalar_struct_pack_width;
const parse_codegen_type_expr = codegen_collect_util.parse_codegen_type_expr;
const parse_type_union_layout_from_name = codegen_collect_structs.parse_type_union_layout_from_name;
const substitute_generic_type_owned = codegen_collect_util.substitute_generic_type_owned;
const call_head_at = codegen_imports.call_head_at;
const expr_call_head = codegen_imports.expr_call_head;
const imported_alias_context_for_tokens = codegen_imports.imported_alias_context_for_tokens;
const is_managed_local_type = codegen_emit_wasi.is_managed_local_type;
const is_tuple_type_name = codegen_emit_wasi.is_tuple_type_name;
const tuple_arity = codegen_emit_wasi.tuple_arity;
const tuple_element_type_at = codegen_emit_wasi.tuple_element_type_at;
const tuple_scalar_leaf_storage_byte_width_ctx = codegen_emit_wasi.tuple_scalar_leaf_storage_byte_width_ctx;
const ManagedPayloadBinding = codegen_storage_layout.ManagedPayloadBinding;
const stmt_contains_storage_agg_literal = codegen_emit_storage_values.stmt_contains_storage_agg_literal;
const find_local_name = codegen_emit_storage_values.find_local_name;
const infer_expr_type = codegen_storage_layout.infer_expr_type;
const find_func_decl_for_call_head = codegen_storage_layout.find_func_decl_for_call_head;
const substitute_struct_field_type = codegen_storage_layout.substitute_struct_field_type;
const managed_payload_elem_type_from_name = codegen_storage_layout.managed_payload_elem_type_from_name;
const emit_zero_value_for_type = codegen_emit_struct.emit_zero_value_for_type;
const stmt_contains_struct_literal_expr = codegen_emit_struct.stmt_contains_struct_literal_expr;
const field_visible_from_tokens = codegen_emit_struct_fields.field_visible_from_tokens;
const field_reflection_local_name_prefix = codegen_emit_struct_fields.field_reflection_local_name_prefix;
const union_payload_comparison_call_branch = codegen_emit_union.union_payload_comparison_call_branch;
const build_payload_enum_union_layout = codegen_emit_union.build_payload_enum_union_layout;
const field_reflection_loop_header = codegen_emit_control.field_reflection_loop_header;
const is_discard_assignment = codegen_emit_control.is_discard_assignment;
const collection_loop_header = codegen_emit_control.collection_loop_header;
const recv_loop_header = codegen_emit_control.recv_loop_header;
const is_dead_managed_alias_binding = codegen_emit_control.is_dead_managed_alias_binding;
const typed_scalar_binding_type = codegen_emit_control.typed_scalar_binding_type;
const inferred_struct_ctor_binding = codegen_emit_control.inferred_struct_ctor_binding;
const inferred_scalar_binding_type = codegen_emit_control.inferred_scalar_binding_type;
const is_managed_local_assignment_stmt = codegen_emit_control.is_managed_local_assignment_stmt;
const is_codegen_scalar_type = codegen_emit_union.is_codegen_scalar_type;
const borrowed_field_meta_local_set = codegen_emit_struct_fields.borrowed_field_meta_local_set;
const collect_field_reflection_body_locals = codegen_emit_struct_fields.collect_field_reflection_body_locals;
const inferred_struct_binding = codegen_emit_struct.inferred_struct_binding;
const typed_struct_binding = codegen_emit_struct.typed_struct_binding;
const append_typed_local_with_decl = codegen_emit_storage_values.append_typed_local_with_decl;
const append_managed_struct_field_meta_local = codegen_emit_storage_values.append_managed_struct_field_meta_local;
const managed_payload_binding = codegen_storage_layout.managed_payload_binding;
const storage_binding_elem_type = codegen_storage_layout.storage_binding_elem_type;

fn stmt_contains_wasi_socket_create(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "(")) continue;
        const import = codegen_imports.find_wasi_host_import_for_tokens(ctx, tokens, tokens[i].lexeme) orelse continue;
        if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.create") or
            std.mem.eql(u8, import.target, "sockets/types/udp-socket.create"))
        {
            return true;
        }
    }
    return false;
}

pub fn emit_self_tail_loop_local_reset(allocator: std.mem.Allocator, func: FuncDecl, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        var is_param = false;
        for (func.params) |param| {
            if (param.callback != null) continue;
            if (std.mem.eql(u8, local.name, param.name)) {
                is_param = true;
                break;
            }
        }
        if (is_param) continue;
        try emit_zero_value_for_type(allocator, ctx, out, local.ty);
        try append_fmt(allocator, out, "    local.set ${s}\n", .{local.name});
    }
}

pub fn collect_body_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) !void {
    try collect_body_locals_with_mode(allocator, tokens, start_idx, end_idx, ctx, out, true);
}

pub fn multi_result_lhs_for_item(
    name: []const u8,
    item: FuncResultItem,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?MultiResultLhs {
    if (item.union_layout) |layout| {
        const union_local = find_union_local(locals.union_locals.items, name) orelse return null;
        if (!unionLayoutsEqual(union_local.layout, layout)) return null;
        return .{ .name = union_local.name, .ty = item.ty, .item = item, .kind = .union_value };
    }

    if (find_struct_local(locals.struct_locals.items, name)) |struct_local| {
        if (!std.mem.eql(u8, struct_local.ty, item.ty)) return null;
        if (find_struct_layout(ctx.struct_layouts, item.ty) != null) {
            const local_name = find_local_name(locals.locals.items, name) orelse return null;
            const local_ty = find_local_type(locals.locals.items, name) orelse return null;
            if (!std.mem.eql(u8, local_ty, item.ty)) return null;
            if (item.abi_len != 1) return null;
            return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .managed };
        }
        const decl = find_struct_decl(ctx.structs, item.ty) orelse return null;
        if (item.abi_len != decl.fields.len) return null;
        return .{ .name = struct_local.name, .ty = item.ty, .item = item, .kind = .unmanaged_struct };
    }

    const local_name = find_local_name(locals.locals.items, name) orelse return null;
    const local_ty = find_local_type(locals.locals.items, name) orelse return null;
    if (!std.mem.eql(u8, local_ty, item.ty)) return null;
    if (item.abi_len != 1) return null;
    if (is_managed_local_type(local_ty, ctx)) {
        return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .managed };
    }
    if (is_codegen_scalar_type(ctx, local_ty)) {
        return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .scalar };
    }
    return null;
}

pub fn collect_callback_call_args(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, binding: CallbackBinding) ![]const CallbackCallArg {
    var out = std.ArrayList(CallbackCallArg).empty;
    errdefer out.deinit(allocator);

    var arg_start = call_head.args_start;
    var idx: usize = 0;
    while (arg_start < call_head.args_end) {
        if (idx >= binding.lambda_params.len or idx >= binding.shape.param_types.len) return error.NoMatchingCall;
        const arg_end = find_arg_end(tokens, arg_start, call_head.args_end);
        const range = trim_parens(tokens, arg_start, arg_end);
        const actual_name: ?[]const u8 = if (range.end == range.start + 1 and tokens[range.start].kind == .ident)
            tokens[range.start].lexeme
        else
            null;
        const arg_ty = binding.shape.param_types[idx] orelse infer_expr_type(tokens, arg_start, arg_end, locals, ctx) orelse return error.NoMatchingCall;
        try out.append(allocator, .{
            .source_name = binding.lambda_params[idx],
            .actual_name = actual_name,
            .ty = arg_ty,
            .expr_tokens = tokens,
            .expr_start = arg_start,
            .expr_end = arg_end,
        });
        idx += 1;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (idx != binding.lambda_params.len) return error.NoMatchingCall;
    return out.toOwnedSlice(allocator);
}

pub fn func_variadic_param_index(func: FuncDecl) ?usize {
    for (func.params, 0..) |param, idx| {
        if (param.variadic) return idx;
    }
    return null;
}

fn append_struct_binding_field_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    out: *LocalSet,
    local_name: []const u8,
    struct_ty: []const u8,
    decl: StructDecl,
    substitute: bool,
) CodegenError!void {
    if (find_struct_layout(ctx.struct_layouts, struct_ty) != null) {
        try out.append_borrowed_local(allocator, local_name, struct_ty, true);
        for (decl.fields) |field| {
            const field_ty = if (substitute)
                try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, &out.owned_names)
            else
                field.ty;
            try append_managed_struct_field_meta_local(allocator, out, local_name, field.name, field_ty);
        }
        try out.ensure_storage_write_temps(allocator);
        return;
    }
    for (decl.fields) |field| {
        const field_ty = if (substitute)
            try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, &out.owned_names)
        else
            field.ty;
        try append_local_field(allocator, out, tokens, ctx, local_name, field.name, field_ty);
    }
}

pub fn collect_body_locals_with_mode(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet, recurse_nested: bool) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_contains_string_literal(tokens, i, stmt_end) or
            stmt_contains_field_name_intrinsic(tokens, i, stmt_end) or
            stmt_contains_storage_agg_literal(tokens, i, stmt_end) or
            stmt_contains_struct_literal_expr(tokens, i, stmt_end) or
            stmt_contains_get_intrinsic(tokens, i, stmt_end) or
            stmt_contains_storage_comparison_intrinsic(tokens, i, stmt_end) or
            stmt_contains_nil_comparison_call(tokens, i, stmt_end) or
            stmt_contains_union_payload_comparison_call(tokens, i, stmt_end, out, ctx))
        {
            try out.ensure_storage_write_temps(allocator);
        }
        if (stmt_contains_struct_literal_expr(tokens, i, stmt_end)) {
            try out.ensure_struct_literal_tmp(allocator);
        }
        if (stmt_contains_variadic_user_call(tokens, i, stmt_end, out, ctx)) {
            try out.ensure_storage_write_temps(allocator);
            try out.ensure_variadic_pack_tmp(allocator);
        }
        if (stmt_contains_numeric_select_intrinsic(tokens, i, stmt_end)) {
            try out.ensure_numeric_select_temps(allocator);
        }
        if (stmt_contains_wasi_socket_create(tokens, i, stmt_end, ctx)) {
            try out.ensure_wasi_family_tmp(allocator);
        }
        if (is_discard_assignment(tokens, i, stmt_end)) {
            i = stmt_end;
            continue;
        }
        if (try is_dead_managed_alias_binding(allocator, tokens, i, stmt_end, end_idx, out, ctx)) {
            i = stmt_end;
            continue;
        }
        if (recurse_nested and try collect_loop_block_locals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Loop block locals collected recursively.
        } else if (recurse_nested and try collect_if_block_locals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Block locals collected recursively.
        } else if (recurse_nested and try collect_defer_block_locals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Cleanup block locals collected recursively.
        } else if (try typed_union_binding_layout(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |layout| {
            defer freeUnionLayout(allocator, layout);
            const local_layout = try cloneUnionLayout(allocator, layout);
            try out.append_union_local(allocator, tokens[i].lexeme, local_layout, true, true);
        } else if (try inferred_union_call_binding(allocator, tokens, i, stmt_end, out, ctx, &out.owned_names)) |binding| {
            errdefer if (binding.owns_layout) freeUnionLayout(allocator, binding.layout);
            try out.append_union_local(allocator, tokens[i].lexeme, binding.layout, true, binding.owns_layout);
        } else if (typed_scalar_binding_type(tokens, i, stmt_end, ctx)) |ty| {
            try out.append_borrowed_local(allocator, tokens[i].lexeme, ty, true);
        } else if (!has_local(out.locals.items, tokens[i].lexeme) and
            find_struct_local(out.struct_locals.items, tokens[i].lexeme) == null and
            inferred_struct_ctor_binding(tokens, i, stmt_end, ctx.structs) != null)
        {
            // Unmanaged pure-scalar structs live in struct_locals + field slots (`out.n`),
            // not as a single `out` scalar local. Reassignment (e.g. `out = @field_set(...)`)
            // must not invent a field-reflection-scoped shadow binding.
            const decl = inferred_struct_ctor_binding(tokens, i, stmt_end, ctx.structs).?;
            const local_name = try out.append_struct_local(allocator, tokens[i].lexeme, decl.name, true);
            try append_struct_binding_field_locals(allocator, tokens, ctx, out, local_name, decl.name, decl, false);
        } else if (!has_local(out.locals.items, tokens[i].lexeme) and
            find_struct_local(out.struct_locals.items, tokens[i].lexeme) == null and
            inferred_struct_binding(tokens, i, stmt_end, out, ctx) != null)
        {
            const binding = inferred_struct_binding(tokens, i, stmt_end, out, ctx).?;
            const local_name = try out.append_struct_local(allocator, tokens[i].lexeme, binding.ty, true);
            try append_struct_binding_field_locals(allocator, tokens, ctx, out, local_name, binding.ty, binding.decl, true);
        } else if (!has_local(out.locals.items, tokens[i].lexeme) and inferred_scalar_binding_type(tokens, i, stmt_end, out, ctx) != null) {
            const ty = inferred_scalar_binding_type(tokens, i, stmt_end, out, ctx).?;
            try out.append_borrowed_local(allocator, tokens[i].lexeme, ty, true);
        } else if (!has_local(out.locals.items, tokens[i].lexeme) and inferred_managed_payload_binding(tokens, i, stmt_end, out, ctx) != null) {
            const binding = inferred_managed_payload_binding(tokens, i, stmt_end, out, ctx).?;
            if (is_tuple_type_name(binding.elem_ty) and tuple_scalar_leaf_storage_byte_width_ctx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.append_storage_local_with_type(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensure_storage_write_temps(allocator);
            if (tuple_scalar_leaf_storage_byte_width_ctx(binding.elem_ty, ctx) != null) {
                try out.ensure_tuple_pack_temps(allocator);
            }
        } else if (try typed_managed_payload_binding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
            if (is_tuple_type_name(binding.elem_ty) and tuple_scalar_leaf_storage_byte_width_ctx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.append_storage_local_with_type(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensure_storage_write_temps(allocator);
            if (tuple_scalar_leaf_storage_byte_width_ctx(binding.elem_ty, ctx) != null) {
                try out.ensure_tuple_pack_temps(allocator);
            }
        } else if (managed_payload_binding(tokens, i, stmt_end)) |binding| {
            if (is_tuple_type_name(binding.elem_ty) and tuple_scalar_leaf_storage_byte_width_ctx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.append_storage_local_with_type(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensure_storage_write_temps(allocator);
            if (tuple_scalar_leaf_storage_byte_width_ctx(binding.elem_ty, ctx) != null) {
                try out.ensure_tuple_pack_temps(allocator);
            }
        } else if (storage_binding_elem_type(tokens, i, stmt_end)) |raw_elem_ty| {
            const elem_ty = try substitute_generic_type_owned(allocator, raw_elem_ty, ctx.type_bindings, &out.owned_names);
            // Scheme A: scalar + managed handle + pure-scalar nested struct slots.
            if (is_tuple_type_name(elem_ty) and tuple_scalar_leaf_storage_byte_width_ctx(elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.append_storage_local(allocator, tokens[i].lexeme, elem_ty, true);
            try out.ensure_storage_write_temps(allocator);
            if (tuple_scalar_leaf_storage_byte_width_ctx(elem_ty, ctx) != null) {
                try out.ensure_tuple_pack_temps(allocator);
            }
        } else if (try collect_multi_result_assignment_locals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Multi-result inferred locals collected.
        } else if (is_managed_local_assignment_stmt(tokens, i, stmt_end, out, ctx)) {
            try out.ensure_storage_write_temps(allocator);
        } else if (multi_result_assignment_needs_managed_tmp(tokens, i, stmt_end, out, ctx)) {
            if (!has_local(out.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
                try out.append_borrowed_local(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
            }
        } else if (try typed_struct_binding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
            const local_name = try out.append_struct_local(allocator, tokens[i].lexeme, binding.ty, true);
            try append_struct_binding_field_locals(allocator, tokens, ctx, out, local_name, binding.ty, binding.decl, true);
        } else if (try typed_tuple_binding_type(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |tuple_ty| {
            const local_name = try out.append_struct_local(allocator, tokens[i].lexeme, tuple_ty, true);
            try append_tuple_local_fields(allocator, out, tokens, ctx, local_name, tuple_ty);
        }
        i = stmt_end;
    }
}

// --- helpers relocated from codegen_pipeline (domain split) ---

pub fn stmt_contains_variadic_user_call(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = call_head_at(tokens, i, end_idx) orelse continue;
        if (call_head.is_intrinsic) continue;
        const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse {
            i = call_head.args_end;
            continue;
        };
        if (func_has_variadic_param(func)) return true;
        i = call_head.args_end;
    }
    return false;
}

pub fn stmt_contains_nil_comparison_call(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = call_head_at(tokens, i, end_idx) orelse continue;
        if (!call_head.is_intrinsic) {
            i = call_head.args_end;
            continue;
        }
        const call_name = tokens[call_head.name_idx].lexeme;
        if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) {
            i = call_head.args_end;
            continue;
        }
        const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
        if (first_end == call_head.args_start or first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) {
            i = call_head.args_end;
            continue;
        }
        const second_start = first_end + 1;
        const second_end = find_arg_end(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) {
            i = call_head.args_end;
            continue;
        }
        const first_nil = first_end == call_head.args_start + 1 and tok_eq(tokens[call_head.args_start], "nil");
        const second_nil = second_end == second_start + 1 and tok_eq(tokens[second_start], "nil");
        if (first_nil or second_nil) return true;
        i = call_head.args_end;
    }
    return false;
}

pub fn stmt_contains_union_payload_comparison_call(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = call_head_at(tokens, i, end_idx) orelse continue;
        if (!call_head.is_intrinsic) {
            i = call_head.args_end;
            continue;
        }
        const call_name = tokens[call_head.name_idx].lexeme;
        if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) {
            i = call_head.args_end;
            continue;
        }
        if (union_payload_comparison_call_branch(tokens, call_head.args_start, call_head.args_end, locals, ctx) != null) return true;
        i = call_head.args_end;
    }
    return false;
}

pub fn append_loop_value_local(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    value_name: []const u8,
    elem_ty: []const u8,
    origin: SourceOrigin,
) !void {
    if (has_local(out.locals.items, value_name)) return;
    if (is_tuple_type_name(elem_ty)) {
        const local_name = try out.append_struct_local_with_origin(allocator, value_name, elem_ty, true, origin);
        try append_tuple_local_fields(allocator, out, tokens, ctx, local_name, elem_ty);
        try out.ensure_tuple_pack_temps(allocator);
        return;
    }
    try out.append_borrowed_local_with_origin(allocator, value_name, elem_ty, true, origin);
}

pub fn collect_collection_loop_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    header: anytype,
    ctx: CodegenContext,
    out: *LocalSet,
) !void {
    try append_loop_index_local(allocator, out, start_idx);
    if (header.source_is_expr) {
        try append_loop_source_storage_local(allocator, out, start_idx, header.source_ty, header.elem_ty);
    }
    if (is_managed_local_type(header.elem_ty, ctx)) {
        try out.ensure_storage_write_temps(allocator);
    }
    if (header.value_name) |value_name| {
        try append_loop_value_local(allocator, out, tokens, ctx, value_name, header.elem_ty, .collection_value);
    }
    if (header.index_name) |index_name| {
        if (!has_local(out.locals.items, index_name)) {
            try out.append_borrowed_local(allocator, index_name, "usize", true);
        }
    }
}

pub fn collect_recv_loop_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    header: anytype,
    ctx: CodegenContext,
    out: *LocalSet,
) !void {
    try append_loop_count_local(allocator, out, start_idx);
    if (is_managed_local_type(header.elem_ty, ctx)) {
        try out.ensure_storage_write_temps(allocator);
    }
    if (header.value_name) |value_name| {
        try append_loop_value_local(allocator, out, tokens, ctx, value_name, header.elem_ty, .recv_value);
    }
    if (header.count_name) |count_name| {
        if (!has_local(out.locals.items, count_name)) {
            try out.append_borrowed_local(allocator, count_name, "usize", true);
        }
    }
}

pub fn collect_loop_block_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tok_eq(tokens[start_idx], "loop")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    if (field_reflection_loop_header(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collect_field_reflection_loop_locals(allocator, tokens, header, ctx, out);
        return true;
    }
    if (collection_loop_header(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collect_collection_loop_locals(allocator, tokens, start_idx, header, ctx, out);
    } else if (recv_loop_header(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collect_recv_loop_locals(allocator, tokens, start_idx, header, ctx, out);
    }

    try collect_body_locals(allocator, tokens, open_brace + 1, close_brace, ctx, out);
    return true;
}

pub fn collect_field_reflection_loop_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, header: FieldReflectionLoopHeader, ctx: CodegenContext, out: *LocalSet) CodegenError!void {
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!field_visible_from_tokens(field, header.decl, tokens)) continue;
        const prefix = try field_reflection_local_name_prefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        var field_locals = try borrowed_field_meta_local_set(allocator, out, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collect_field_reflection_body_locals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &field_locals);
        try append_decl_only_locals(allocator, out, &field_locals);
        visible_index += 1;
    }
}

pub fn append_loop_index_local(allocator: std.mem.Allocator, out: *LocalSet, loop_id: usize) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_index_{d}", .{loop_id});
    if (has_local(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.append_owned_local_with_origin(allocator, name, "usize", .compiler_temp);
}

pub fn append_loop_count_local(allocator: std.mem.Allocator, out: *LocalSet, loop_id: usize) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_count_{d}", .{loop_id});
    if (has_local(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.append_owned_local_with_origin(allocator, name, "usize", .compiler_temp);
}

pub fn collect_if_block_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    if (start_idx + 4 > end_idx) return false;
    if (!tok_eq(tokens[start_idx], "if")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return false;
    try collect_body_locals(allocator, tokens, open_brace + 1, close_brace, ctx, out);

    if (close_brace + 1 == end_idx) return true;
    if (close_brace + 1 >= end_idx or !tok_eq(tokens[close_brace + 1], "else")) return false;
    if (close_brace + 2 >= end_idx) return false;

    if (tok_eq(tokens[close_brace + 2], "if")) {
        _ = try collect_if_block_locals(allocator, tokens, close_brace + 2, end_idx, ctx, out);
        return true;
    }
    if (!tok_eq(tokens[close_brace + 2], "{")) return false;
    const close_else = find_matching_in_range(tokens, close_brace + 2, "{", "}", end_idx) catch return false;
    if (close_else + 1 != end_idx) return false;
    try collect_body_locals(allocator, tokens, close_brace + 3, close_else, ctx, out);
    return true;
}

pub fn collect_defer_block_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tok_eq(tokens[start_idx], "defer")) return false;
    if (!tok_eq(tokens[start_idx + 1], "{")) return false;
    const close_brace = find_matching_in_range(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collect_body_locals(allocator, tokens, start_idx + 2, close_brace, ctx, &cleanup_locals);
    try append_decl_only_locals(allocator, out, &cleanup_locals);
    return true;
}

pub fn append_decl_only_locals(allocator: std.mem.Allocator, out: *LocalSet, source: *const LocalSet) !void {
    for (source.locals.items) |local| {
        if (has_local(out.locals.items, local.name)) continue;
        const name = try allocator.dupe(u8, local.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const ty = try allocator.dupe(u8, local.ty);
        errdefer allocator.free(ty);
        try out.owned_names.append(allocator, ty);
        errdefer _ = out.owned_names.pop();

        try out.locals.append(allocator, .{
            .name = name,
            .source_name = local.source_name,
            .ty = ty,
            .origin = local.origin,
            .emit_decl = local.emit_decl,
            .release_on_scope_exit = false,
        });
    }
    for (source.storage_locals.items) |storage| {
        if (find_storage_local_exact(out.storage_locals.items, storage.name) != null) continue;
        const name = try allocator.dupe(u8, storage.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const elem_ty = try allocator.dupe(u8, storage.elem_ty);
        errdefer allocator.free(elem_ty);
        try out.owned_names.append(allocator, elem_ty);
        errdefer _ = out.owned_names.pop();

        const ty = try allocator.dupe(u8, storage.ty);
        errdefer allocator.free(ty);
        try out.owned_names.append(allocator, ty);
        errdefer _ = out.owned_names.pop();

        try out.storage_locals.append(allocator, .{
            .name = name,
            .source_name = storage.source_name,
            .ty = ty,
            .elem_ty = elem_ty,
            .origin = storage.origin,
        });
    }
    for (source.struct_locals.items) |struct_local| {
        if (find_struct_local_exact(out.struct_locals.items, struct_local.name) != null) continue;
        const name = try allocator.dupe(u8, struct_local.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const ty = try allocator.dupe(u8, struct_local.ty);
        errdefer allocator.free(ty);
        try out.owned_names.append(allocator, ty);
        errdefer _ = out.owned_names.pop();

        try out.struct_locals.append(allocator, .{
            .name = name,
            .source_name = struct_local.source_name,
            .ty = ty,
            .origin = struct_local.origin,
        });
    }
    for (source.union_locals.items) |union_local| {
        if (find_union_local_exact(out.union_locals.items, union_local.name) != null) continue;
        const name = try allocator.dupe(u8, union_local.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();
        const layout = try cloneUnionLayout(allocator, union_local.layout);
        try out.union_locals.append(allocator, .{
            .name = name,
            .source_name = union_local.source_name,
            .layout = layout,
            .owns_layout = true,
            .origin = union_local.origin,
        });
    }
}

pub fn append_local_field(allocator: std.mem.Allocator, out: *LocalSet, tokens: []const lexer.Token, ctx: CodegenContext, base: []const u8, field: []const u8, ty: []const u8) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    if (is_tuple_type_name(ty)) {
        try out.owned_names.append(allocator, name);
        const local_name = try out.append_struct_local(allocator, name, ty, true);
        try append_tuple_local_fields(allocator, out, tokens, ctx, local_name, ty);
        return;
    }
    // Pure-scalar unmanaged struct slot (e.g. Tuple.0 : Point) — nested field locals, not a single i32.
    if (find_struct_decl(ctx.structs, ty)) |decl| {
        if (find_struct_layout(ctx.struct_layouts, ty) == null and pure_scalar_struct_pack_width(decl, ctx.structs) != null) {
            try out.owned_names.append(allocator, name);
            const local_name = try out.append_struct_local(allocator, name, ty, true);
            for (decl.fields) |sf| {
                const field_ty = try substitute_struct_field_type(allocator, decl, ty, sf.ty, &out.owned_names);
                try append_local_field(allocator, out, tokens, ctx, local_name, sf.name, field_ty);
            }
            return;
        }
    }
    if (try parse_type_union_layout_from_name(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, &out.owned_names)) |layout| {
        errdefer freeUnionLayout(allocator, layout);
        const exists = find_union_local_exact(out.union_locals.items, name) != null;
        if (!exists) {
            errdefer allocator.free(name);
            try out.owned_names.append(allocator, name);
            errdefer _ = out.owned_names.pop();
        } else {
            defer allocator.free(name);
        }
        return out.append_union_local(allocator, name, layout, true, true);
    }
    // Named payload enum type on field/local path
    if (find_payload_enum_decl(ctx.payload_enums, ty)) |decl| {
        const layout = try build_payload_enum_union_layout(allocator, decl, tokens, ctx.structs, ctx.struct_layouts, &out.owned_names);
        errdefer freeUnionLayout(allocator, layout);
        const exists = find_union_local_exact(out.union_locals.items, name) != null;
        if (!exists) {
            errdefer allocator.free(name);
            try out.owned_names.append(allocator, name);
            errdefer _ = out.owned_names.pop();
        } else {
            defer allocator.free(name);
        }
        return out.append_union_local(allocator, name, layout, true, true);
    }
    try out.append_owned_local(allocator, name, ty);
}

pub fn stmt_contains_string_literal(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .string) continue;
        if (tokens[i].lexeme.len < 2 or tokens[i].lexeme[0] != '"') continue;
        return true;
    }
    return false;
}

pub fn stmt_contains_storage_comparison_intrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tok_eq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        const name = tokens[i + 1].lexeme;
        if (std.mem.eql(u8, name, "eq") or std.mem.eql(u8, name, "ne")) return true;
    }
    return false;
}

pub fn stmt_contains_field_name_intrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tok_eq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "field_name")) return true;
    }
    return false;
}

pub fn stmt_contains_get_intrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tok_eq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "get") or
            std.mem.eql(u8, tokens[i + 1].lexeme, "field_get")) return true;
    }
    return false;
}

pub fn stmt_contains_numeric_select_intrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tok_eq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        const name = tokens[i + 1].lexeme;
        if (std.mem.eql(u8, name, "abs") or std.mem.eql(u8, name, "min") or std.mem.eql(u8, name, "max")) {
            return true;
        }
    }
    return false;
}

pub fn typed_union_binding_layout(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?UnionLayout {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    // Named payload enum: `m Message = …`
    if (eq_idx == start_idx + 2 and tokens[start_idx + 1].kind == .ident) {
        const ty_name = publicDeclName(tokens[start_idx + 1].lexeme);
        if (find_payload_enum_decl(ctx.payload_enums, ty_name)) |decl| {
            return try build_payload_enum_union_layout(allocator, decl, tokens, ctx.structs, ctx.struct_layouts, owned_types);
        }
    }
    return try parse_union_type_layout(
        allocator,
        tokens,
        start_idx + 1,
        eq_idx,
        ctx.structs,
        ctx.struct_layouts,
        imported_alias_context_for_tokens(ctx.imported_alias_ctx, tokens),
        owned_types,
    );
}

pub fn inferred_union_call_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?InferredUnionBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tok_eq(tokens[start_idx + 1], "=")) return null;
    const range = trim_parens(tokens, start_idx + 2, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    if (find_func_decl_for_call_head(tokens, call_head, locals, ctx)) |func| {
        if (func.result_union) |layout| {
            return .{ .layout = layout, .owns_layout = false };
        }
        return null;
    }
    if (codegen_callbacks.infer_generic_call_union_result) |infer_fn| {
        if (try infer_fn(allocator, tokens, call_head, locals, ctx, owned_types)) |layout| {
            return .{ .layout = layout, .owns_layout = true };
        }
    }
    return null;
}

pub fn append_tuple_local_fields(allocator: std.mem.Allocator, out: *LocalSet, tokens: []const lexer.Token, ctx: CodegenContext, base: []const u8, tuple_ty: []const u8) CodegenError!void {
    const arity = tuple_arity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tuple_element_type_at(tuple_ty, idx) orelse return error.UnsupportedLowering;
        var field_buf: [32]u8 = undefined;
        const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{idx});
        try append_local_field(allocator, out, tokens, ctx, base, field_name, elem_ty);
    }
}

pub fn func_has_variadic_param(func: FuncDecl) bool {
    return func_variadic_param_index(func) != null;
}

pub fn find_storage_local_exact(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

pub fn find_struct_local_exact(locals: []const StructLocal, name: []const u8) ?StructLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

// --- more helpers from codegen_pipeline ---

pub fn inferred_managed_payload_binding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?ManagedPayloadBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tok_eq(tokens[start_idx + 1], "=")) return null;
    const ty = infer_expr_type(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    const elem_ty = managed_payload_elem_type_from_name(ty) orelse return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

pub fn typed_managed_payload_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?ManagedPayloadBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed = (try parse_codegen_type_expr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed.next_idx != eq_idx) return null;
    const ty = try substitute_generic_type_owned(allocator, parsed.ty, ctx.type_bindings, owned_types);
    const elem_ty = managed_payload_elem_type_from_name(ty) orelse return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

/// Bind one multi-result LHS name from a function result item (skip `_`).
fn collect_one_multi_result_lhs_local(
    allocator: std.mem.Allocator,
    name: []const u8,
    item: FuncResultItem,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!void {
    if (std.mem.eql(u8, name, "_")) return;
    if (item.union_layout) |layout| {
        if (find_union_local(out.union_locals.items, name) != null) return;
        const cloned = try cloneUnionLayout(allocator, layout);
        try out.append_union_local(allocator, name, cloned, true, true);
        return;
    }
    if (find_local_type(out.locals.items, name) != null) return;
    if (find_struct_local(out.struct_locals.items, name) != null) return;
    if (find_storage_local(out.storage_locals.items, name) != null) return;
    try append_typed_local_with_decl(allocator, out, name, item.ty, ctx, true);
}

pub fn collect_multi_result_assignment_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    const eq_idx = find_top_level_token(tokens, start_idx, end_idx, "=") orelse return false;
    if (find_top_level_token(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trim_parens(tokens, eq_idx + 1, end_idx);
    const call_head = expr_call_head(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, out, ctx) orelse return false;
    if (func.results.len <= 1 or func.result_items.len == 0) return false;

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return error.NoMatchingCall;
        const lhs_end = find_arg_end(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return error.NoMatchingCall;
        try collect_one_multi_result_lhs_local(allocator, tokens[lhs_start].lexeme, func.result_items[item_idx], ctx, out);

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tok_eq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (item_idx != func.result_items.len) return error.NoMatchingCall;
    return true;
}

pub fn multi_result_assignment_needs_managed_tmp(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    const eq_idx = find_top_level_token(tokens, start_idx, end_idx, "=") orelse return false;
    if (find_top_level_token(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trim_parens(tokens, eq_idx + 1, end_idx);
    const call_head = expr_call_head(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len <= 1) return false;
    if (func.result_items.len == 0) return false;

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return false;
        const lhs_end = find_arg_end(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return false;
        const lhs = multi_result_lhs_for_item(tokens[lhs_start].lexeme, func.result_items[item_idx], locals, ctx) orelse return false;
        if (lhs.kind == .managed) return true;

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tok_eq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    return false;
}

pub fn typed_tuple_binding_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed_ty.next_idx != eq_idx) return null;
    const ty = try substitute_generic_type_owned(allocator, parsed_ty.ty, ctx.type_bindings, owned_types);
    if (!is_tuple_type_name(ty)) return null;
    return ty;
}
