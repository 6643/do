//! Struct field access, field metadata, and reflection emission.
//!
//! Shared field-shape and narrowing helpers live here so aggregate construction
//! can depend on this module without a reverse import.

const std = @import("std");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const IsComparisonNarrowing = model.IsComparisonNarrowing;
const NilComparisonNarrowing = model.NilComparisonNarrowing;
const TypedStructBinding = model.TypedStructBinding;
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_ownership = @import("codegen_ownership.zig");
const find_top_level_guard_loop_control = codegen_ownership.findTopLevelGuardLoopControl;
const label_for_loop_start = codegen_ownership.labelForLoopStart;
const codegen_union_layout = @import("codegen_union_layout.zig");
const ownership_facts = @import("ownership_facts.zig");
const tok_eq = codegen_tokens.tok_eq;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const public_decl_name = codegen_names.public_decl_name;
const append_fmt = codegen_names.append_fmt;
const string_token_body = codegen_tokens.string_token_body;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const find_stmt_end = codegen_tokens.find_stmt_end;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const StructDecl = model.StructDecl;
const StructField = model.StructField;
const StructLayout = model.StructLayout;
const StructLocal = model.StructLocal;
const UnionLocal = model.UnionLocal;
const FuncResultItem = model.FuncResultItem;
const DeferContext = context.DeferContext;
const CallLastUseMoveContext = context.CallLastUseMoveContext;
const LastUseManagedMoveSource = context.LastUseManagedMoveSource;
const LoopControl = context.LoopControl;
const FieldMetaLocal = model.FieldMetaLocal;
const FieldReflectionLoopHeader = context.FieldReflectionLoopHeader;
const FieldStaticValue = context.FieldStaticValue;
const FieldReflectionIfParts = context.FieldReflectionIfParts;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const STORAGE_WRITE_TARGET_TMP_LOCAL = constants.STORAGE_WRITE_TARGET_TMP_LOCAL;
const find_struct_local = context.findStructLocal;
const find_union_local = context.findUnionLocal;
const has_local = context.hasLocal;
const UnionLayout = codegen_union_layout.UnionLayout;
const free_union_layout = codegen_union_layout.free_union_layout;
const union_layouts_equal = codegen_union_layout.union_layouts_equal;
const find_struct_decl = gen_collect_util.findStructDecl;
const find_struct_layout = gen_collect_util.findStructLayout;
const parse_codegen_type_expr = gen_collect_util.parseCodegenTypeExpr;
const parse_type_union_layout_from_name = codegen_collect_structs.parse_type_union_layout_from_name;
const substitute_generic_type_owned = gen_collect_util.substituteGenericTypeOwned;
const expr_call_head = codegen_imports.exprCallHead;
const is_managed_local_type = codegen_emit_wasi.is_managed_local_type;
const is_tuple_type_name = codegen_emit_wasi.is_tuple_type_name;
const codegen_wasm_type = codegen_emit_wasi.codegen_wasm_type;
const append_load_for_payload_type = codegen_emit_wasi.append_load_for_payload_type;
const struct_field_payload_offset = codegen_emit_wasi.struct_field_payload_offset;
const find_union_branch_by_type = codegen_emit_wasi.find_union_branch_by_type;
const codegen_emit_storage_values = @import("codegen_emit_storage_values.zig");
const emit_storage_u8_raw_string_value = codegen_emit_storage_values.emit_storage_u8_raw_string_value;
const emit_tuple_local_set = codegen_emit_storage_values.emit_tuple_local_set;
const append_store_for_payload_type = codegen_emit_storage_values.append_store_for_payload_type;
const is_direct_managed_local_expr = codegen_emit_storage_values.is_direct_managed_local_expr;
const substitute_struct_field_type = codegen_emit_storage_values.substitute_struct_field_type;
const is_struct_literal_rhs = codegen_emit_storage_values.is_struct_literal_rhs;
const find_local_field_type = codegen_emit_storage_values.find_local_field_type;
const infer_expr_type = codegen_emit_storage_values.infer_expr_type;
const direct_managed_last_use_move_source = codegen_emit_storage_values.direct_managed_last_use_move_source;
const has_registered_defer_stmt = codegen_emit_storage_values.has_registered_defer_stmt;
const token_range_uses_ident = codegen_emit_storage_values.token_range_uses_ident;
const find_field_meta_local = codegen_emit_storage_values.find_field_meta_local;
const field_from_meta = codegen_emit_storage_values.field_from_meta;
const find_struct_field = codegen_emit_storage_values.find_struct_field;
const is_dot_ident = codegen_emit_storage_values.is_dot_ident;
const clone_local_set = codegen_storage_layout.clone_local_set;
const type_base_name = codegen_emit_storage_values.type_base_name;
pub fn emit_field_reflection_static_if(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    i: usize,
    stmt_end: usize,
    segment_start: *usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const parts = field_reflection_if_parts(tokens, i, stmt_end) orelse return false;
    const condition = field_static_bool_expr(tokens, parts.cond_start, parts.cond_end, locals, ctx) orelse return false;
    if (segment_start.* < i) {
        try codegen_callbacks.emit_body(allocator, tokens, segment_start.*, i, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, null, out);
    }
    try emit_field_reflection_static_branch(
        allocator,
        tokens,
        parts,
        condition,
        stmt_end,
        body_start,
        locals,
        return_cleanup_locals,
        control_cleanup_locals,
        ctx,
        result_tys,
        result_items,
        result_struct,
        result_union,
        loop_ctx,
        defer_ctx,
        return_label,
        out,
    );
    return true;
}

pub fn collect_field_reflection_static_if(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    i: usize,
    stmt_end: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!bool {
    const parts = field_reflection_if_parts(tokens, i, stmt_end) orelse return false;
    const condition = field_static_bool_expr(tokens, parts.cond_start, parts.cond_end, out, ctx) orelse return false;
    try collect_field_reflection_static_branch(allocator, tokens, parts, condition, stmt_end, ctx, out);
    return true;
}

pub fn emit_field_reflection_static_branch(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    parts: FieldReflectionIfParts,
    condition: bool,
    stmt_end: usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!void {
    if (condition) {
        try emit_field_reflection_body(allocator, tokens, parts.then_start, parts.then_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
        return;
    }
    if (parts.else_if_start) |nested_if| {
        try emit_field_reflection_body(allocator, tokens, nested_if, stmt_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
        return;
    }
    if (parts.else_start) |else_start| {
        try emit_field_reflection_body(allocator, tokens, else_start, parts.else_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
}

pub fn collect_field_reflection_static_branch(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    parts: FieldReflectionIfParts,
    condition: bool,
    stmt_end: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!void {
    if (condition) {
        try collect_field_reflection_body_locals(allocator, tokens, parts.then_start, parts.then_end, ctx, out);
        return;
    }
    if (parts.else_if_start) |nested_if| {
        try collect_field_reflection_body_locals(allocator, tokens, nested_if, stmt_end, ctx, out);
        return;
    }
    if (parts.else_start) |else_start| {
        try collect_field_reflection_body_locals(allocator, tokens, else_start, parts.else_end, ctx, out);
    }
}

pub fn emit_field_reflection_body(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, out: *std.ArrayList(u8)) CodegenError!void {
    var i = start_idx;
    var segment_start = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (try emit_field_reflection_static_if(
            allocator,
            tokens,
            i,
            stmt_end,
            &segment_start,
            body_start,
            locals,
            return_cleanup_locals,
            control_cleanup_locals,
            ctx,
            result_tys,
            result_items,
            result_struct,
            result_union,
            loop_ctx,
            defer_ctx,
            return_label,
            out,
        )) {
            i = stmt_end;
            segment_start = stmt_end;
            continue;
        }
        i = stmt_end;
    }
    if (segment_start < end_idx) {
        try codegen_callbacks.emit_body(allocator, tokens, segment_start, end_idx, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, null, out);
    }
}

pub fn emit_field_reflection_loop_block(allocator: std.mem.Allocator, tokens: []const lexer.Token, header: FieldReflectionLoopHeader, body_start: usize, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    const source_label = label_for_loop_start(tokens, header.loop_idx);
    const break_label = try std.fmt.allocPrint(allocator, "__field_break_{d}", .{header.loop_idx});
    defer allocator.free(break_label);

    try append_fmt(allocator, out, "    ;; field-reflect-loop type={s}\n", .{header.decl.name});
    try append_fmt(allocator, out, "    block ${s}\n", .{break_label});
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!field_visible_from_tokens(field, header.decl, tokens)) continue;
        const prefix = try field_reflection_local_name_prefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        const continue_label = try std.fmt.allocPrint(allocator, "__field_continue_{d}_{d}", .{ header.loop_idx, visible_index });
        defer allocator.free(continue_label);
        var field_locals = try borrowed_field_meta_local_set(allocator, locals, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collect_field_reflection_body_locals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &field_locals);
        var field_cleanup_locals = try field_reflection_scoped_cleanup_local_set(allocator, &field_locals, prefix);
        defer field_cleanup_locals.deinit(allocator);
        const field_loop = LoopControl{
            .parent = if (loop_ctx) |*control| control else null,
            .source_label = source_label,
            .break_label = break_label,
            .continue_label = continue_label,
            .cleanup_locals = &field_cleanup_locals,
            .defer_ctx = defer_ctx orelse return error.NoMatchingCall,
        };
        try append_fmt(allocator, out, "    block ${s}\n", .{continue_label});
        var active_return_cleanup_locals = try merge_return_cleanup_locals(allocator, return_cleanup_locals, &field_cleanup_locals);
        defer active_return_cleanup_locals.deinit(allocator);
        var active_control_cleanup_locals = try merge_return_cleanup_locals(allocator, control_cleanup_locals, &field_cleanup_locals);
        defer active_control_cleanup_locals.deinit(allocator);
        try emit_field_reflection_body(allocator, tokens, header.open_brace + 1, header.close_brace, body_start, &field_locals, &active_return_cleanup_locals, &active_control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, field_loop, defer_ctx, return_label, out);
        if (body_can_reach_end(tokens, header.open_brace + 1, header.close_brace)) {
            try emit_block_release_managed_locals(allocator, &field_cleanup_locals, ctx, out);
        }
        try out.appendSlice(allocator, "    end\n");
        visible_index += 1;
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn emit_managed_struct_field_set(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, body_end: usize, allow_last_use_move: bool, target_name: []const u8, field_name: []const u8, field_offset: usize, field_ty: []const u8, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    const move_ctx = if (allow_last_use_move) CallLastUseMoveContext{
        .stmt_end = value_end,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    } else null;
    if (!try codegen_callbacks.emit_expr_with_move_context(allocator, tokens, value_start, value_end, locals, ctx, field_ty, if (move_ctx) |*ctx_info| ctx_info else null, out)) return error.NoMatchingCall;
    const move_source = if (allow_last_use_move)
        direct_managed_last_use_move_source(tokens, value_start, value_end, body_end, target_name, locals, ctx, defer_ctx)
    else
        null;
    if (move_source == null and is_direct_managed_local_expr(tokens, value_start, value_end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try append_fmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});

    const struct_local = find_struct_local(locals.struct_locals.items, target_name) orelse return error.NoMatchingCall;
    const decl = find_struct_decl(ctx.structs, struct_local.ty) orelse return error.NoMatchingCall;
    const layout = find_struct_layout(ctx.struct_layouts, struct_local.ty) orelse return error.NoMatchingCall;

    try append_fmt(allocator, out, "    local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try append_fmt(allocator, out, "      ;; arc-managed-struct-reuse {s}.{s}\n", .{ target_name, field_name });
    try append_fmt(allocator, out, "      ;; arc-overwrite-release {s}.{s}\n", .{ target_name, field_name });
    try append_fmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try append_managed_struct_field_ptr(allocator, out, target_name, field_offset);
    try append_load_for_payload_type(allocator, out, field_ty);
    try out.appendSlice(allocator, "      i32.ne\n");
    try out.appendSlice(allocator, "      if\n");
    try append_managed_struct_field_ptr(allocator, out, target_name, field_offset);
    try append_load_for_payload_type(allocator, out, field_ty);
    try out.appendSlice(allocator, "        call $__arc_dec\n");
    try out.appendSlice(allocator, "      end\n");
    try append_managed_struct_field_ptr(allocator, out, target_name, field_offset);
    try append_fmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try append_store_for_payload_type(allocator, out, field_ty);
    try append_fmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "    else\n");
    try append_fmt(allocator, out, "      ;; arc-managed-struct-clone-set {s}.{s}\n", .{ target_name, field_name });
    try emit_managed_struct_clone_with_field_set(allocator, target_name, field_name, decl, struct_local.ty, layout, out);
    try out.appendSlice(allocator, "    end\n");
    try append_fmt(allocator, out, "    local.set ${s}\n", .{target_name});
    if (move_source) |source| {
        try append_fmt(allocator, out, "    ;; field-set-move {s}\n", .{source.source_name});
        try emit_zero_value_for_type(allocator, ctx, out, field_ty);
        try append_fmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
}

pub fn emit_struct_field_value(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, field_ty: []const u8, copy_managed: bool, out: *std.ArrayList(u8)) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parse_type_union_layout_from_name(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer free_union_layout(allocator, layout);
        if (!try codegen_callbacks.emit_union_value(allocator, tokens, start_idx, end_idx, locals, ctx, layout, copy_managed, null, out)) {
            return error.NoMatchingCall;
        }
        return;
    }
    if (!try codegen_callbacks.emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, field_ty, out)) {
        return error.NoMatchingCall;
    }
}

pub fn emit_struct_field_meta_set_assignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    if (start_idx + 6 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const struct_local = find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!tok_eq(tokens[start_idx + 1], "=")) return false;

    var name_idx = start_idx + 2;
    if (tok_eq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= end_idx) return false;
    }
    if (!std.mem.eql(u8, tokens[name_idx].lexeme, "field_set")) return false;
    if (name_idx + 1 >= end_idx or !tok_eq(tokens[name_idx + 1], "(")) return false;

    const open_paren = name_idx + 1;
    const args_start = open_paren + 1;
    const close_paren = find_matching_in_range(tokens, open_paren, "(", ")", end_idx) catch return false;
    if (close_paren + 1 != end_idx) return false;

    const first_end = find_arg_end(tokens, args_start, close_paren);
    if (first_end != args_start + 1 or !std.mem.eql(u8, tokens[args_start].lexeme, tokens[start_idx].lexeme)) return false;
    if (first_end >= close_paren or !tok_eq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, close_paren);
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;
    const meta = find_field_meta_local(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, type_base_name(struct_local.ty), meta.struct_name)) return false;
    if (field_end >= close_paren or !tok_eq(tokens[field_end], ",")) return false;

    const value_start = field_end + 1;
    const field = field_from_meta(ctx, meta) orelse return false;
    const field_name = public_decl_name(field.name);
    const field_ty = find_local_field_type(locals.locals.items, struct_local.name, field_name) orelse field.ty;

    try append_fmt(allocator, out, "    ;; field-set name={s} field={s}\n", .{
        tokens[start_idx].lexeme,
        field_name,
    });

    if (find_struct_layout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const decl = find_struct_decl(ctx.structs, struct_local.ty) orelse return false;
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return false;
        if (is_managed_struct_field(layout, field_name)) {
            try emit_managed_struct_field_set(
                allocator,
                tokens,
                value_start,
                close_paren,
                body_end,
                allow_last_use_move,
                tokens[start_idx].lexeme,
                field_name,
                field_offset,
                field_ty,
                locals,
                defer_ctx,
                ctx,
                out,
            );
            return true;
        }
        try append_managed_struct_field_ptr(allocator, out, tokens[start_idx].lexeme, field_offset);
        if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try append_store_for_payload_type(allocator, out, field_ty);
        return true;
    }

    if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try append_fmt(allocator, out, "    local.set ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}

pub fn field_static_values_equal(left: FieldStaticValue, right: FieldStaticValue) bool {
    return switch (left) {
        .bool => |l| switch (right) {
            .bool => |r| l == r,
            else => false,
        },
        .int => |l| switch (right) {
            .int => |r| l == r,
            else => false,
        },
        .text => |l| switch (right) {
            .text => |r| std.mem.eql(u8, l, r),
            else => false,
        },
    };
}

pub fn field_reflection_local_visible(name: []const u8, scoped_prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "__field_")) return true;
    return std.mem.startsWith(u8, name, scoped_prefix);
}

pub fn append_union_payload_local_get(allocator: std.mem.Allocator, out: *std.ArrayList(u8), base: []const u8, idx: usize) !void {
    try append_fmt(allocator, out, "    local.get ${s}.__union_payload_{d}\n", .{ base, idx });
}

pub fn append_union_tag_local_get(allocator: std.mem.Allocator, out: *std.ArrayList(u8), base: []const u8) !void {
    try append_fmt(allocator, out, "    local.get ${s}.__union_tag\n", .{base});
}

pub fn append_union_tag_local_set(allocator: std.mem.Allocator, out: *std.ArrayList(u8), base: []const u8) !void {
    try append_fmt(allocator, out, "    local.set ${s}.__union_tag\n", .{base});
}

pub fn is_managed_struct_field(layout: StructLayout, field_name: []const u8) bool {
    for (layout.managed_fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) return true;
    }
    return false;
}

pub fn struct_local_source_name(local: StructLocal) []const u8 {
    return local.source_name orelse local.name;
}

pub fn field_reflection_local_name_prefix(allocator: std.mem.Allocator, header: FieldReflectionLoopHeader, visible_index: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "__field_{d}_{d}_", .{ header.open_brace, visible_index });
}

pub fn emit_struct_field_local_get(allocator: std.mem.Allocator, tokens: []const lexer.Token, base: []const u8, field_name: []const u8, field_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, copy_managed: bool, out: *std.ArrayList(u8)) CodegenError!void {
    _ = tokens;
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, field_name });
    defer allocator.free(union_local_name);
    if (find_union_local(locals.union_locals.items, union_local_name)) |union_local| {
        for (union_local.layout.payload_tys, 0..) |payload_ty, idx| {
            try append_union_payload_local_get(allocator, out, union_local.name, idx);
            if (copy_managed and is_managed_local_type(payload_ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
        }
        try append_union_tag_local_get(allocator, out, union_local.name);
        return;
    }
    try append_fmt(allocator, out, "    local.get ${s}.{s}\n", .{ base, field_name });
    if (copy_managed and is_managed_local_type(field_ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
}

pub fn emit_struct_field_local_set(allocator: std.mem.Allocator, tokens: []const lexer.Token, base: []const u8, field_name: []const u8, field_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, field_name });
    defer allocator.free(union_local_name);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parse_type_union_layout_from_name(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer free_union_layout(allocator, layout);
        const union_local = find_union_local(locals.union_locals.items, union_local_name) orelse return error.NoMatchingCall;
        if (!union_layouts_equal(union_local.layout, layout)) return error.NoMatchingCall;
        var idx = union_local.layout.payload_tys.len + 1;
        while (idx > 0) {
            idx -= 1;
            if (idx == union_local.layout.payload_tys.len) {
                try append_union_tag_local_set(allocator, out, union_local.name);
            } else {
                try append_union_payload_local_set(allocator, out, union_local.name, idx);
            }
        }
        return;
    }
    if (is_tuple_type_name(field_ty)) {
        return try emit_tuple_local_set(allocator, union_local_name, field_ty, ctx, out);
    }
    try append_fmt(allocator, out, "    local.set ${s}.{s}\n", .{ base, field_name });
}

pub fn emit_struct_fields_from_local(allocator: std.mem.Allocator, tokens: []const lexer.Token, struct_local: StructLocal, decl: StructDecl, locals: *const LocalSet, ctx: CodegenContext, copy_managed: bool, out: *std.ArrayList(u8)) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    for (decl.fields) |field| {
        const field_ty = try substitute_struct_field_type(allocator, decl, struct_local.ty, field.ty, &owned_types);
        try emit_struct_field_local_get(allocator, tokens, struct_local.name, public_decl_name(field.name), field_ty, locals, ctx, copy_managed, out);
    }
}

pub fn emit_managed_struct_clone_with_field_set(allocator: std.mem.Allocator, target_name: []const u8, target_field_name: []const u8, decl: StructDecl, struct_ty: []const u8, layout: StructLayout, out: *std.ArrayList(u8)) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    try append_fmt(allocator, out, "      i32.const {d}\n", .{layout.payload_bytes});
    try append_fmt(allocator, out, "      i32.const {d}\n", .{layout.type_id});
    try out.appendSlice(allocator, "      call $__arc_alloc\n");
    try append_fmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});

    for (decl.fields) |field| {
        const field_name = public_decl_name(field.name);
        const field_ty = try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, &owned_types);
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return error.NoMatchingCall;

        try append_managed_struct_field_ptr(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL, field_offset);
        if (std.mem.eql(u8, field_name, target_field_name)) {
            try append_fmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try append_store_for_payload_type(allocator, out, field_ty);
            continue;
        }

        try append_managed_struct_field_ptr(allocator, out, target_name, field_offset);
        try append_load_for_payload_type(allocator, out, field_ty);
        if (is_managed_struct_field(layout, field_name)) {
            try out.appendSlice(allocator, "      call $__arc_inc\n");
        }
        try append_store_for_payload_type(allocator, out, field_ty);
    }

    try append_fmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "      call $__arc_dec\n");
    try append_fmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
}

pub fn append_managed_struct_field_ptr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), local_name: []const u8, field_offset: usize) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n", .{local_name});
    try out.appendSlice(allocator, "    call $__arc_payload\n");
    try append_fmt(allocator, out, "    i32.const {d}\n", .{field_offset});
    try out.appendSlice(allocator, "    i32.add\n");
}

pub fn field_reflection_if_parts(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?FieldReflectionIfParts {
    if (start_idx + 4 > end_idx) return null;
    if (!tok_eq(tokens[start_idx], "if")) return null;
    const open_brace = find_top_level_block_open(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return null;
    var parts = FieldReflectionIfParts{
        .cond_start = start_idx + 1,
        .cond_end = open_brace,
        .then_start = open_brace + 1,
        .then_end = close_brace,
    };
    if (close_brace + 1 == end_idx) return parts;
    if (close_brace + 1 >= end_idx or !tok_eq(tokens[close_brace + 1], "else")) return null;
    if (close_brace + 2 >= end_idx) return null;
    if (tok_eq(tokens[close_brace + 2], "if")) {
        parts.else_if_start = close_brace + 2;
        return parts;
    }
    if (!tok_eq(tokens[close_brace + 2], "{")) return null;
    const close_else = find_matching_in_range(tokens, close_brace + 2, "{", "}", end_idx) catch return null;
    if (close_else + 1 != end_idx) return null;
    parts.else_start = close_brace + 3;
    parts.else_end = close_else;
    return parts;
}

pub fn field_static_bool_expr(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?bool {
    if (field_static_value(tokens, start_idx, end_idx, locals, ctx)) |value| {
        return switch (value) {
            .bool => |b| b,
            else => null,
        };
    }

    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic and std.mem.eql(u8, call_name, "not")) {
        const arg_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return null;
        return !(field_static_bool_expr(tokens, call_head.args_start, arg_end, locals, ctx) orelse return null);
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "and") or std.mem.eql(u8, call_name, "or"))) {
        var arg_start = call_head.args_start;
        var saw_arg = false;
        while (arg_start < call_head.args_end) {
            const arg_end = find_arg_end(tokens, arg_start, call_head.args_end);
            const value = field_static_bool_expr(tokens, arg_start, arg_end, locals, ctx) orelse return null;
            saw_arg = true;
            if (std.mem.eql(u8, call_name, "and") and !value) return false;
            if (std.mem.eql(u8, call_name, "or") and value) return true;
            arg_start = arg_end;
            if (arg_start < call_head.args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (!saw_arg) return null;
        return std.mem.eql(u8, call_name, "and");
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne"))) {
        const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
        if (first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return null;
        const second_start = first_end + 1;
        const second_end = find_arg_end(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return null;
        const left = field_static_value(tokens, call_head.args_start, first_end, locals, ctx) orelse return null;
        const right = field_static_value(tokens, second_start, second_end, locals, ctx) orelse return null;
        const is_equal = field_static_values_equal(left, right);
        return if (std.mem.eql(u8, call_name, "eq")) is_equal else !is_equal;
    }
    return null;
}

pub fn field_static_value(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?FieldStaticValue {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .number) return .{ .int = std.fmt.parseUnsigned(usize, tok.lexeme, 10) catch return null };
        if (tok.kind == .string) return .{ .text = string_token_body(tok.lexeme) orelse return null };
        if (tok_eq(tok, "true")) return .{ .bool = true };
        if (tok_eq(tok, "false")) return .{ .bool = false };
        return null;
    }

    const call_head = expr_call_head(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "field_name")) {
        const meta = single_field_meta_arg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = field_from_meta(ctx, meta) orelse return null;
        return .{ .text = public_decl_name(field.name) };
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        const meta = single_field_meta_arg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        return .{ .int = meta.visible_index };
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        const meta = single_field_meta_arg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = field_from_meta(ctx, meta) orelse return null;
        return .{ .bool = field.default_start != null };
    }
    return null;
}

pub fn field_visible_from_tokens(field: StructField, decl: StructDecl, tokens: []const lexer.Token) bool {
    if (!is_private_field_name(field.name)) return true;
    return module_tokens_equal(decl.tokens, tokens);
}

pub fn is_private_field_name(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}

pub fn typed_struct_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?TypedStructBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed_ty.next_idx != eq_idx) return null;
    const ty = try substitute_generic_type_owned(allocator, parsed_ty.ty, ctx.type_bindings, owned_types);
    const decl = find_struct_decl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
}

pub fn inferred_struct_binding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?TypedStructBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tok_eq(tokens[start_idx + 1], "=")) return null;
    const ty = infer_expr_type(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    const decl = find_struct_decl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
}

pub fn emit_managed_struct_expr_field_get(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, field_start: usize, field_end: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (field_end != field_start + 1 or !is_dot_ident(tokens[field_start].lexeme)) return false;
    if (value_end == value_start + 1 and tokens[value_start].kind == .ident) return false;
    const struct_ty = infer_expr_type(tokens, value_start, value_end, locals, ctx) orelse return false;
    const layout = find_struct_layout(ctx.struct_layouts, struct_ty) orelse return false;
    const decl = find_struct_decl(ctx.structs, struct_ty) orelse return false;
    const field_name = public_decl_name(tokens[field_start].lexeme);
    const field = find_struct_field(decl, field_name) orelse return false;
    const field_offset = struct_field_payload_offset(decl, field_name) orelse return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const field_ty = try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, &owned_types);

    if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, struct_ty, out)) return false;
    try append_fmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try append_managed_struct_field_ptr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, field_offset);
    try append_load_for_payload_type(allocator, out, field_ty);
    if (is_managed_struct_field(layout, field_name)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try append_fmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
    return true;
}

pub fn emit_field_reflection_intrinsic(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, move_ctx: ?*const CallLastUseMoveContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (std.mem.eql(u8, call_name, "field_name")) {
        const meta = single_field_meta_arg(tokens, start_idx, end_idx, locals) orelse return false;
        const field = field_from_meta(ctx, meta) orelse return false;
        try emit_storage_u8_raw_string_value(allocator, public_decl_name(field.name), STORAGE_OVERWRITE_TMP_LOCAL, ctx, out);
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        const meta = single_field_meta_arg(tokens, start_idx, end_idx, locals) orelse return false;
        try append_fmt(allocator, out, "    i32.const {d}\n", .{meta.visible_index});
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        const meta = single_field_meta_arg(tokens, start_idx, end_idx, locals) orelse return false;
        const field = field_from_meta(ctx, meta) orelse return false;
        try append_fmt(allocator, out, "    i32.const {d}\n", .{@intFromBool(field.default_start != null)});
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_get")) {
        return try emit_field_get_call(allocator, tokens, start_idx, end_idx, locals, ctx, move_ctx, out);
    }
    return false;
}

pub fn emit_field_get_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, move_ctx: ?*const CallLastUseMoveContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, end_idx);
    if (field_end != end_idx) return false;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;

    const name = tokens[start_idx].lexeme;
    const struct_local = find_struct_local(locals.struct_locals.items, name) orelse return false;
    const meta = find_field_meta_local(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, type_base_name(struct_local.ty), meta.struct_name)) return false;
    const field = field_from_meta(ctx, meta) orelse return false;
    const field_name = public_decl_name(field.name);

    if (find_struct_layout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const decl = find_struct_decl(ctx.structs, struct_local.ty) orelse return false;
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return false;
        const move_source = if (move_ctx) |ctx_info|
            try field_get_last_use_move_source(allocator, tokens, start_idx, end_idx, struct_local, field.ty, ctx_info.*, locals, ctx)
        else
            null;
        try append_fmt(allocator, out, "    local.get ${s}\n", .{struct_local.name});
        try out.appendSlice(allocator, "    call $__arc_payload\n");
        try append_fmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        try append_load_for_payload_type(allocator, out, field.ty);
        if (is_managed_struct_field(layout, field_name) and move_source == null) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        if (move_source) |source| {
            try append_fmt(allocator, out, "    ;; field-get-move {s}.{s}\n", .{ source.source_name, field_name });
            try emit_zero_value_for_type(allocator, ctx, out, field.ty);
            try append_managed_struct_field_ptr(allocator, out, struct_local.name, field_offset);
            try append_store_for_payload_type(allocator, out, field.ty);
        }
        return true;
    }

    if (try emit_unmanaged_struct_field_get(allocator, tokens, struct_local, field_name, field.ty, locals, ctx, out)) {
        return true;
    }
    try append_fmt(allocator, out, "    local.get ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}

pub fn emit_unmanaged_struct_field_get(allocator: std.mem.Allocator, tokens: []const lexer.Token, struct_local: StructLocal, field_name: []const u8, field_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const layout = (try parse_type_union_layout_from_name(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) orelse return false;
    defer free_union_layout(allocator, layout);
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ struct_local.name, field_name });
    defer allocator.free(union_local_name);
    const union_local = find_union_local(locals.union_locals.items, union_local_name) orelse return false;
    if (!union_layouts_equal(union_local.layout, layout)) return false;
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try append_union_payload_local_get(allocator, out, union_local.name, idx);
        if (is_managed_local_type(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try append_union_tag_local_get(allocator, out, union_local.name);
    return true;
}

pub fn borrowed_field_meta_local_set(allocator: std.mem.Allocator, parent: *const LocalSet, meta: FieldMetaLocal, scoped_prefix: []const u8) !LocalSet {
    var out = LocalSet{};
    errdefer out.deinit(allocator);
    for (parent.locals.items) |local| {
        if (!field_reflection_local_visible(local.name, scoped_prefix)) continue;
        try out.locals.append(allocator, local);
    }
    for (parent.struct_locals.items) |local| {
        if (!field_reflection_local_visible(local.name, scoped_prefix)) continue;
        try out.struct_locals.append(allocator, local);
    }
    for (parent.storage_locals.items) |local| {
        if (!field_reflection_local_visible(local.name, scoped_prefix)) continue;
        try out.storage_locals.append(allocator, local);
    }
    for (parent.union_locals.items) |union_local| {
        if (!field_reflection_local_visible(union_local.name, scoped_prefix)) continue;
        try out.union_locals.append(allocator, .{
            .name = union_local.name,
            .source_name = union_local.source_name,
            .layout = union_local.layout,
            .owns_layout = false,
        });
    }
    try out.field_meta_locals.appendSlice(allocator, parent.field_meta_locals.items);
    try out.field_meta_locals.append(allocator, meta);
    return out;
}

pub fn single_field_meta_arg(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?FieldMetaLocal {
    const arg_end = find_arg_end(tokens, start_idx, end_idx);
    if (arg_end != end_idx) return null;
    const range = trim_parens(tokens, start_idx, arg_end);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return find_field_meta_local(locals.field_meta_locals.items, tokens[range.start].lexeme);
}

pub fn field_get_last_use_move_source(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, struct_local: StructLocal, field_ty: []const u8, move_ctx: CallLastUseMoveContext, locals: *const LocalSet, ctx: CodegenContext) CodegenError!?LastUseManagedMoveSource {
    if (!is_managed_local_type(field_ty, ctx)) return null;

    const body_start = move_ctx.body_start;
    const source_name = struct_local_source_name(struct_local);
    const decl_end = (try fresh_struct_literal_binding_stmt_end(
        allocator,
        tokens,
        body_start,
        start_idx,
        source_name,
        struct_local.ty,
        locals,
        ctx,
    )) orelse return null;
    const fresh_source_gap = token_range_uses_ident(tokens, decl_end, start_idx, source_name);
    const after_expr_use = token_range_uses_ident(tokens, end_idx, move_ctx.stmt_end, source_name);
    const body_rest_use = token_range_uses_ident(tokens, move_ctx.stmt_end, move_ctx.body_end, source_name);
    const candidate = ownership_facts.MoveCandidate{
        .kind = .field_get,
        .source = .{
            .source_name = source_name,
            .actual_name = struct_local.name,
            .origin = .fresh_local,
        },
        .expr_range = .{ .start = start_idx, .end = end_idx },
        .context = .{
            .body = .{ .start = move_ctx.body_start, .end = move_ctx.body_end },
            .statement = .{ .end = move_ctx.stmt_end },
            .defer_visible = has_registered_defer_stmt(tokens, move_ctx.defer_ctx),
            .allow_last_use_move = move_ctx.allow_last_use_move,
            .allow_field_read_move = move_ctx.allow_field_read_move,
        },
        .future_use = .{
            .fresh_source_gap = if (fresh_source_gap) .{ .start = decl_end, .end = start_idx } else null,
            .after_expr = if (after_expr_use) .{ .start = end_idx, .end = move_ctx.stmt_end } else null,
            .body_rest = if (body_rest_use) .{ .start = move_ctx.stmt_end, .end = move_ctx.body_end } else null,
        },
    };
    const decision = ownership_facts.decideFieldGetMove(candidate);
    if (!decision.accepted) return null;
    return .{
        .source_name = source_name,
        .actual_name = struct_local.name,
        .origin = struct_local.origin,
    };
}

pub fn fresh_struct_literal_binding_stmt_end(allocator: std.mem.Allocator, tokens: []const lexer.Token, body_start: usize, expr_start: usize, source_name: []const u8, struct_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext) CodegenError!?usize {
    var i = body_start;
    while (i < expr_start) {
        const stmt_end = find_stmt_end(tokens, i, expr_start);
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, source_name)) {
            const eq_idx = find_top_level_token(tokens, i + 1, stmt_end, "=") orelse return null;
            if (!is_struct_literal_rhs(tokens, eq_idx + 1, stmt_end)) return null;

            var owned_types = std.ArrayList([]const u8).empty;
            defer {
                for (owned_types.items) |owned| allocator.free(owned);
                owned_types.deinit(allocator);
            }

            if (try typed_struct_binding(allocator, tokens, i, stmt_end, ctx, &owned_types)) |binding| {
                if (std.mem.eql(u8, binding.ty, struct_ty)) return stmt_end;
                return null;
            }
            if (inferred_struct_binding(tokens, i, stmt_end, locals, ctx)) |binding| {
                if (std.mem.eql(u8, binding.ty, struct_ty)) return stmt_end;
            }
            return null;
        }
        i = stmt_end;
    }
    return null;
}

// re-export codegen_ownership
pub const emit_block_release_managed_locals = codegen_ownership.emitBlockReleaseManagedLocals;
pub const body_can_reach_end = codegen_ownership.bodyCanReachEnd;
pub fn emit_zero_value_for_type(allocator: std.mem.Allocator, ctx: CodegenContext, out: *std.ArrayList(u8), ty: []const u8) !void {
    try append_fmt(allocator, out, "    {s}.const 0\n", .{codegen_wasm_type(ctx, ty)});
}

pub fn collect_field_reflection_body_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (try collect_field_reflection_static_if(allocator, tokens, i, stmt_end, ctx, out)) {
            i = stmt_end;
            continue;
        }
        try codegen_callbacks.collect_body_locals(allocator, tokens, i, stmt_end, ctx, out);
        try apply_collect_guard_return_narrowing(allocator, tokens, i, stmt_end, out, ctx);
        try apply_guard_loop_control_narrowing(allocator, tokens, i, stmt_end, out, ctx);
        i = stmt_end;
    }
}

pub fn append_union_payload_local_set(allocator: std.mem.Allocator, out: *std.ArrayList(u8), base: []const u8, idx: usize) !void {
    try append_fmt(allocator, out, "    local.set ${s}.__union_payload_{d}\n", .{ base, idx });
}

pub fn apply_guard_return_nil_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet) !void {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return;
    const return_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = nil_comparison_narrowing(tokens, start_idx + 1, return_idx, locals) orelse return;
    if (narrowing.non_nil_when_true) return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
}

pub fn apply_guard_return_is_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext) !void {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return;
    const return_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = try is_comparison_narrowing(allocator, tokens, start_idx + 1, return_idx, locals, ctx) orelse return;
    const payload_ty = union_local_single_remaining_payload_type(narrowing.union_local, narrowing.payload_ty) orelse return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
}

pub fn apply_guard_loop_control_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext) !void {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return;
    const control_idx = find_top_level_guard_loop_control(tokens, start_idx + 1, end_idx) orelse return;

    if (nil_comparison_narrowing(tokens, start_idx + 1, control_idx, locals)) |narrowing| {
        if (!narrowing.non_nil_when_true) {
            try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
        }
    }

    if (try is_comparison_narrowing(allocator, tokens, start_idx + 1, control_idx, locals, ctx)) |narrowing| {
        const payload_ty = union_local_single_remaining_payload_type(narrowing.union_local, narrowing.payload_ty) orelse return;
        try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
    }
}

pub fn nil_comparison_narrowing(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?NilComparisonNarrowing {
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) return null;

    const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
    if (first_end == call_head.args_start or first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, call_head.args_end);
    if (second_end != call_head.args_end) return null;

    const left_ident = single_ident_expr(tokens, call_head.args_start, first_end);
    const right_ident = single_ident_expr(tokens, second_start, second_end);
    const left_nil = single_nil_expr(tokens, call_head.args_start, first_end);
    const right_nil = single_nil_expr(tokens, second_start, second_end);
    const name = if (left_ident != null and right_nil)
        left_ident.?
    else if (right_ident != null and left_nil)
        right_ident.?
    else
        return null;

    const union_local = find_union_local(locals.union_locals.items, name) orelse return null;
    const payload_ty = union_local_single_non_nil_payload_type(union_local) orelse return null;
    return .{
        .union_local = union_local,
        .payload_ty = payload_ty,
        .non_nil_when_true = std.mem.eql(u8, call_name, "ne"),
    };
}

pub fn is_comparison_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) CodegenError!?IsComparisonNarrowing {
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "is")) return null;

    const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
    if (first_end != call_head.args_start + 1 or tokens[call_head.args_start].kind != .ident) return null;
    if (first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return null;
    const union_local = find_union_local(locals.union_locals.items, tokens[call_head.args_start].lexeme) orelse return null;
    const type_start = first_end + 1;
    const type_end = trim_trailing_comma(tokens, type_start, call_head.args_end);
    if (type_start >= type_end) return null;
    if (find_top_level_token(tokens, type_start, type_end, "|") != null) return null;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, type_start, type_end, &owned_types)) orelse return null;
    if (parsed_ty.next_idx != type_end) return null;
    const target_ty = try substitute_generic_type_owned(allocator, parsed_ty.ty, ctx.type_bindings, &owned_types);
    if (std.mem.eql(u8, target_ty, "nil")) return null;
    const branch = find_union_branch_by_type(union_local.layout, target_ty) orelse return null;
    if (branch.tag == 0 and std.mem.eql(u8, branch.ty, "nil")) return null;
    // Narrow to payload type so `x [u8] = m` works after `@is(m, Text)`.
    // Flat unions: branch.ty is the arm type. Payload enums: payload_type is the arm payload.
    return .{
        .union_local = union_local,
        .payload_ty = branch.payload_type orelse branch.ty,
    };
}

pub fn single_ident_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return tokens[range.start].lexeme;
}

pub fn single_nil_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trim_parens(tokens, start_idx, end_idx);
    return range.end == range.start + 1 and tok_eq(tokens[range.start], "nil");
}

pub fn union_local_single_non_nil_payload_type(union_local: UnionLocal) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

pub fn union_local_single_remaining_payload_type(union_local: UnionLocal, excluded_ty: []const u8) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (std.mem.eql(u8, branch.ty, excluded_ty)) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

pub fn trim_trailing_comma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx < end_idx and tok_eq(tokens[end_idx - 1], ",")) return end_idx - 1;
    return end_idx;
}

pub fn apply_collect_guard_return_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext) !void {
    try apply_guard_return_nil_narrowing(allocator, tokens, start_idx, end_idx, locals);
    try apply_guard_return_is_narrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

pub fn merge_return_cleanup_locals(allocator: std.mem.Allocator, parent: *const LocalSet, direct: *const LocalSet) !LocalSet {
    var out = try clone_local_set(allocator, parent);
    errdefer out.deinit(allocator);
    for (direct.locals.items) |local| {
        if (has_local(out.locals.items, local.name)) continue;
        try out.locals.append(allocator, local);
    }
    return out;
}

pub fn field_reflection_scoped_cleanup_local_set(allocator: std.mem.Allocator, source: *const LocalSet, scoped_prefix: []const u8) !LocalSet {
    var out = LocalSet{};
    errdefer out.deinit(allocator);
    for (source.locals.items) |local| {
        if (!std.mem.startsWith(u8, local.name, scoped_prefix)) continue;
        try out.locals.append(allocator, .{
            .name = local.name,
            .source_name = local.source_name,
            .ty = local.ty,
            .emit_decl = false,
            .release_on_scope_exit = true,
        });
    }
    return out;
}
