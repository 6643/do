//! Storage set, put, copy, and alias operation emission.
//!
//! Storage payload offsets, ownership actions, and WAT instruction sequences are
//! preserved at this operation boundary.

const storage_layout = @import("codegen_storage_layout.zig");
const storage_element_byte_width_for_type = storage_layout.storage_element_byte_width_for_type;
const storage_pack_layout_for_elem = storage_layout.storage_pack_layout_for_elem;
const union_local_default_payload_type = storage_layout.union_local_default_payload_type;

const std = @import("std");
const lexer = @import("lexer.zig");
const storage_wat = @import("wat_storage.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const gen_import = @import("gen_import.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_emit_tuple = @import("codegen_emit_tuple.zig");
const ownership = @import("ownership.zig");
const tokEq = codegen_tokens.tok_eq;
const findArgEnd = codegen_tokens.find_arg_end;
const trimParens = codegen_tokens.trim_parens;
const appendFmt = codegen_names.append_fmt;
const LocalSet = context.LocalSet;
const Local = model.Local;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const StructLayout = model.StructLayout;
const UnionLocal = model.UnionLocal;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const STORAGE_WRITE_INDEX_TMP_LOCAL = constants.STORAGE_WRITE_INDEX_TMP_LOCAL;
const STORAGE_PUT_SOURCE_TMP_LOCAL = constants.STORAGE_PUT_SOURCE_TMP_LOCAL;
const STORAGE_WRITE_LEN_TMP_LOCAL = constants.STORAGE_WRITE_LEN_TMP_LOCAL;
const STORAGE_WRITE_SCAN_TMP_LOCAL = constants.STORAGE_WRITE_SCAN_TMP_LOCAL;
const STORAGE_WRITE_TARGET_TMP_LOCAL = constants.STORAGE_WRITE_TARGET_TMP_LOCAL;
const STORAGE_WRITE_NEXT_TMP_LOCAL = constants.STORAGE_WRITE_NEXT_TMP_LOCAL;
const TUPLE_PACK_BASE_TMP_LOCAL = constants.TUPLE_PACK_BASE_TMP_LOCAL;
const STORAGE_PAYLOAD_HEADER_BYTES = constants.STORAGE_PAYLOAD_HEADER_BYTES;
const TYPE_ID_STORAGE_U8 = constants.TYPE_ID_STORAGE_U8;
const TYPE_ID_STORAGE_MANAGED = constants.TYPE_ID_STORAGE_MANAGED;
const findLocalType = context.findLocalType;
const findUnionLocal = context.findUnionLocal;
const localNameMatches = context.localNameMatches;
const exprCallHead = gen_import.exprCallHead;
const is_managed_local_type = codegen_emit_wasi.is_managed_local_type;
const storage_type_id_for_element = codegen_emit_wasi.storage_type_id_for_element;
const is_tuple_type_name = codegen_emit_wasi.is_tuple_type_name;
const find_storage_primitive_local = codegen_emit_wasi.find_storage_primitive_local;
const emit_storage_len_ptr = codegen_emit_wasi.emit_storage_len_ptr;
const tuple_has_managed_pack_leaf_ctx = codegen_emit_wasi.tuple_has_managed_pack_leaf_ctx;
pub const appendLoadForPayloadTypeWithIndent = codegen_emit_tuple.append_load_for_payload_type_with_indent;
pub const appendLoadTupleScalarLeavesToStackCtx = codegen_emit_tuple.append_load_tuple_scalar_leaves_to_stack_ctx;
pub const appendStoreForPayloadType = codegen_emit_tuple.append_store_for_payload_type;
pub const appendStoreForPayloadTypeWithIndent = codegen_emit_tuple.append_store_for_payload_type_with_indent;
pub const appendStoreTupleLeavesOwningFromStackCtx = codegen_emit_tuple.append_store_tuple_leaves_owning_from_stack_ctx;
pub const appendStoreTupleScalarLeavesFromStackCtx = codegen_emit_tuple.append_store_tuple_scalar_leaves_from_stack_ctx;
pub const emitDecManagedTupleLeavesAtBase = codegen_emit_tuple.emit_dec_managed_tuple_leaves_at_base;
pub const emitIncManagedTupleLeavesAtBase = codegen_emit_tuple.emit_inc_managed_tuple_leaves_at_base;
pub const emitStorageIncCopiedPackElements = codegen_emit_tuple.emit_storage_inc_copied_pack_elements;
pub fn emit_storage_len_ptr_with_indent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, indent: []const u8) !void {
    try storage_wat.emit_storage_len_ptr_with_indent(allocator, out, name, indent);
}

pub fn emit_storage_cap_ptr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    try storage_wat.emit_storage_cap_ptr(allocator, out, name);
}

pub fn emit_storage_cap_ptr_with_indent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, indent: []const u8) !void {
    try storage_wat.emit_storage_cap_ptr_with_indent(allocator, out, name, indent);
}

pub fn emit_storage_bounds_check(allocator: std.mem.Allocator, tokens: []const lexer.Token, offset_start: usize, offset_end: usize, locals: *const LocalSet, ctx: CodegenContext, storage_name: []const u8, width: usize, out: *std.ArrayList(u8)) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{storage_name});
    if (!try codegen_callbacks.emit_expr(allocator, tokens, offset_start, offset_end, locals, ctx, "usize", out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{width});
    try out.appendSlice(allocator, "    call $__storage_check_range\n");
}

pub fn emit_storage_write_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "set")) {
        return try emit_storage_set_call(allocator, tokens, call_head.args_start, call_head.args_end, target_name, locals, ctx, out);
    }
    if (std.mem.eql(u8, call_name, "put")) {
        return try emit_storage_put_call(allocator, tokens, call_head.args_start, call_head.args_end, target_name, locals, ctx, out);
    }
    return false;
}

pub fn emit_storage_set_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return false;
    if (find_storage_primitive_local(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return try emit_storage_set_call(allocator, tokens, start_idx, end_idx, tokens[start_idx].lexeme, locals, ctx, out);
}

pub fn emit_storage_put_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage = find_storage_primitive_local(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const first_value_start = first_end + 1;
    const first_value_end = findArgEnd(tokens, first_value_start, end_idx);
    if (first_value_end == first_value_start) return false;
    if (first_value_start < end_idx and tokEq(tokens[first_value_start], "...")) {
        if (first_value_end != end_idx) return false;
        return try emit_storage_put_spread_call(allocator, tokens, first_value_start + 1, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }
    if (first_value_end == end_idx) {
        return try emit_storage_put_one_call(allocator, tokens, first_value_start, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }

    if (!try emit_storage_put_one_call(allocator, tokens, first_value_start, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});

    var value_start = first_value_end;
    while (value_start < end_idx) {
        if (!tokEq(tokens[value_start], ",")) return false;
        value_start += 1;
        if (value_start >= end_idx) return false;
        if (tokEq(tokens[value_start], "...")) return false;

        const value_end = findArgEnd(tokens, value_start, end_idx);
        if (value_end == value_start) return false;
        if (!try emit_storage_put_one_call(allocator, tokens, value_start, value_end, STORAGE_PUT_SOURCE_TMP_LOCAL, STORAGE_PUT_SOURCE_TMP_LOCAL, storage.elem_ty, locals, ctx, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
        try emit_replace_storage_put_source_tmp(allocator, target_name, out);
        value_start = value_end;
    }

    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    return true;
}

pub fn emit_storage_put_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return false;
    if (find_storage_primitive_local(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return try emit_storage_put_call(allocator, tokens, start_idx, end_idx, tokens[start_idx].lexeme, locals, ctx, out);
}

pub fn emit_storage_put_spread_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, spread_start: usize, spread_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (spread_end != spread_start + 1 or tokens[spread_start].kind != .ident) return false;
    const rest_name = tokens[spread_start].lexeme;
    const rest = find_storage_primitive_local(locals.storage_locals.items, rest_name) orelse return false;
    if (!std.mem.eql(u8, rest.elem_ty, elem_ty)) return false;
    const elem_bytes = storage_element_byte_width_for_type(elem_ty, ctx) orelse return false;

    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    if (is_direct_managed_local_expr(tokens, spread_start, spread_end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 0\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    block $storage_put_spread_done\n");
    try out.appendSlice(allocator, "      loop $storage_put_spread_scan\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emit_storage_len_ptr(allocator, out, rest_name);
    try out.appendSlice(allocator, "        i32.load\n");
    try out.appendSlice(allocator, "        i32.ge_u\n");
    try out.appendSlice(allocator, "        br_if $storage_put_spread_done\n");
    if (is_managed_local_type(elem_ty, ctx)) {
        try emit_storage_element_ptr_from_local_with_indent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, 4, "        ");
        try out.appendSlice(allocator, "        i32.load\n");
        try out.appendSlice(allocator, "        call $__arc_inc\n");
        try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try out.appendSlice(allocator, "        call $__storage_put_managed_borrow\n");
    } else if (std.mem.eql(u8, elem_ty, "u8")) {
        try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try emit_storage_element_ptr_from_local_with_indent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
        try out.appendSlice(allocator, "        call $__storage_put_u8\n");
    } else {
        try emit_storage_put_spread_scalar_element(allocator, rest_name, elem_ty, elem_bytes, ctx, out);
    }
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emit_replace_storage_put_source_tmp(allocator, target_name, out);
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.add\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "        br $storage_put_spread_scan\n");
    try out.appendSlice(allocator, "      end\n");
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    return true;
}

pub fn emit_storage_set_scalar_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, index_start: usize, index_end: usize, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_bytes = storage_element_byte_width_for_type(elem_ty, ctx) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-set-scalar\n");
    try emit_storage_alias_protect(allocator, out, source_name, target_name);
    if (!try codegen_callbacks.emit_expr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    call $__storage_check_range\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try emit_storage_clone_current_len_for_elem(allocator, out, source_name, elem_ty, elem_bytes, ctx);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (is_tuple_type_name(elem_ty)) {
        if (tuple_has_managed_pack_leaf_ctx(elem_ty, ctx)) {
            // Dec replaced managed leaves before writing new ones.
            try emit_storage_element_ptr_from_local(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try emitDecManagedTupleLeavesAtBase(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        }
        if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try emit_storage_element_ptr_from_local(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emit_storage_element_ptr_from_local(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try appendStoreForPayloadType(allocator, out, elem_ty);
    }
    try emit_storage_alias_release(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emit_storage_put_spread_scalar_element(allocator: std.mem.Allocator, rest_name: []const u8, elem_ty: []const u8, elem_bytes: usize, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    try out.appendSlice(allocator, "        ;; storage-put-spread-scalar\n");
    try emit_storage_len_ptr_with_indent(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, "        ");
    try out.appendSlice(allocator, "        i32.load\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "        call $__arc_rc\n");
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.eq\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emit_storage_cap_ptr_with_indent(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, "        ");
    try out.appendSlice(allocator, "        i32.load\n");
    try out.appendSlice(allocator, "        i32.lt_u\n");
    try out.appendSlice(allocator, "        i32.and\n");
    try out.appendSlice(allocator, "        if (result i32)\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "        else\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 1\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try emit_storage_clone_with_len_local_for_elem(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, elem_ty, elem_bytes, STORAGE_WRITE_NEXT_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, ctx);
    try out.appendSlice(allocator, "        end\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (is_tuple_type_name(elem_ty)) {
        try emit_storage_element_ptr_from_local_with_indent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        // Spread copy: load without owning-inc, store without owning-inc (clone path already inced, or unique).
        try appendLoadTupleScalarLeavesToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        try emit_storage_element_ptr_from_local_with_indent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
        try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleScalarLeavesFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        if (tuple_has_managed_pack_leaf_ctx(elem_ty, ctx)) {
            // Unique-append path copies handles without clone-inc; share ownership with source element.
            try emit_storage_element_ptr_from_local_with_indent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
            try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try emitIncManagedTupleLeavesAtBase(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        }
    } else {
        try emit_storage_element_ptr_from_local_with_indent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
        try emit_storage_element_ptr_from_local_with_indent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
        try appendStoreForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
    }
    try emit_storage_len_ptr_with_indent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, "        ");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.add\n");
    try out.appendSlice(allocator, "        i32.store\n");
}

pub fn emit_storage_put_scalar_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_bytes = storage_element_byte_width_for_type(elem_ty, ctx) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-put-scalar\n");
    try emit_storage_alias_protect(allocator, out, source_name, target_name);
    try emit_storage_len_ptr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emit_storage_cap_ptr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.lt_u\n");
    try out.appendSlice(allocator, "    i32.and\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "      i32.const 1\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emit_storage_clone_with_len_local_for_elem(allocator, out, source_name, elem_ty, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, ctx);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (is_tuple_type_name(elem_ty)) {
        if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try emit_storage_element_ptr_from_local(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emit_storage_element_ptr_from_local(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try appendStoreForPayloadType(allocator, out, elem_ty);
    }
    try emit_storage_len_ptr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.add\n");
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_alias_release(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emit_storage_clone_current_len(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_bytes: usize) !void {
    try emit_storage_len_ptr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emit_storage_clone_with_len_local(allocator, out, source_name, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL);
}

pub fn emit_storage_clone_current_len_for_elem(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_ty: []const u8, elem_bytes: usize, ctx: CodegenContext) !void {
    try emit_storage_len_ptr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emit_storage_clone_with_len_local_for_elem(allocator, out, source_name, elem_ty, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, ctx);
}

pub fn emit_storage_clone_managed_current_len(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8) !void {
    try emit_storage_len_ptr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emit_storage_clone_managed_with_len_local(allocator, out, source_name, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL);
}

pub fn emit_storage_clone_managed_with_len_local(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, next_len_local: []const u8, copy_len_local: []const u8) !void {
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.mul\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{TYPE_ID_STORAGE_MANAGED});
    try out.appendSlice(allocator, "      call $__arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{copy_len_local});
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.mul\n");
    try out.appendSlice(allocator, "      memory.copy\n");
    try emit_storage_inc_copied_managed_elements(allocator, out, STORAGE_WRITE_NEXT_TMP_LOCAL, copy_len_local);
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
}

pub fn emit_storage_inc_copied_managed_elements(allocator: std.mem.Allocator, out: *std.ArrayList(u8), storage_local: []const u8, copy_len_local: []const u8) !void {
    try out.appendSlice(allocator, "      ;; storage-managed-clone-inc\n");
    try out.appendSlice(allocator, "      i32.const 0\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "      block $storage_clone_inc_done\n");
    try out.appendSlice(allocator, "        loop $storage_clone_inc_scan\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try appendFmt(allocator, out, "          local.get ${s}\n", .{copy_len_local});
    try out.appendSlice(allocator, "          i32.ge_u\n");
    try out.appendSlice(allocator, "          br_if $storage_clone_inc_done\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{storage_local});
    try out.appendSlice(allocator, "          call $__arc_payload\n");
    try appendFmt(allocator, out, "          i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 4\n");
    try out.appendSlice(allocator, "          i32.mul\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try out.appendSlice(allocator, "          i32.load\n");
    try out.appendSlice(allocator, "          call $__arc_inc\n");
    try out.appendSlice(allocator, "          drop\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 1\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          br $storage_clone_inc_scan\n");
    try out.appendSlice(allocator, "        end\n");
    try out.appendSlice(allocator, "      end\n");
}

pub fn emit_storage_clone_with_len_local(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_bytes: usize, next_len_local: []const u8, copy_len_local: []const u8) !void {
    try emit_storage_clone_with_len_local_typed(allocator, out, source_name, elem_bytes, next_len_local, copy_len_local, TYPE_ID_STORAGE_U8, null);
}

pub fn emit_storage_clone_with_len_local_for_elem(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_ty: []const u8, elem_bytes: usize, next_len_local: []const u8, copy_len_local: []const u8, ctx: CodegenContext) !void {
    const type_id = storage_type_id_for_element(elem_ty, ctx);
    const pack = storage_pack_layout_for_elem(elem_ty, ctx);
    try emit_storage_clone_with_len_local_typed(allocator, out, source_name, elem_bytes, next_len_local, copy_len_local, type_id, pack);
}

pub fn emit_storage_clone_with_len_local_typed(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_bytes: usize, next_len_local: []const u8, copy_len_local: []const u8, type_id: usize, pack_layout: ?StructLayout) !void {
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "      i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "      i32.mul\n");
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{type_id});
    try out.appendSlice(allocator, "      call $__arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{copy_len_local});
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "      i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "      i32.mul\n");
    }
    try out.appendSlice(allocator, "      memory.copy\n");
    if (pack_layout) |layout| {
        try emitStorageIncCopiedPackElements(allocator, out, STORAGE_WRITE_NEXT_TMP_LOCAL, copy_len_local, layout);
    }
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
}

pub fn emit_storage_element_ptr_from_local(allocator: std.mem.Allocator, out: *std.ArrayList(u8), storage_local: []const u8, index_local: []const u8, elem_bytes: usize) !void {
    try storage_wat.emit_storage_element_ptr_from_local(allocator, out, storage_local, index_local, elem_bytes);
}

pub fn emit_storage_element_ptr_from_local_with_indent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), storage_local: []const u8, index_local: []const u8, elem_bytes: usize, indent: []const u8) !void {
    try storage_wat.emit_storage_element_ptr_from_local_with_indent(allocator, out, storage_local, index_local, elem_bytes, indent);
}

pub fn emit_storage_alias_protect(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, target_name: []const u8) !void {
    try storage_wat.emit_storage_alias_protect(allocator, out, source_name, target_name);
}

pub fn emit_storage_alias_release(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, target_name: []const u8) !void {
    try storage_wat.emit_storage_alias_release(allocator, out, source_name, target_name);
}

pub fn is_direct_managed_local_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    return direct_managed_local_expr_name(tokens, start_idx, end_idx, locals, ctx) != null;
}

pub fn emit_replace_storage_put_source_tmp(allocator: std.mem.Allocator, target_name: []const u8, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(allocator, "    ;; storage-put-source-replace\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.ne\n");
    try out.appendSlice(allocator, "    if\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "      i32.ne\n");
    try out.appendSlice(allocator, "      if\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "        call $__arc_dec\n");
    try out.appendSlice(allocator, "      end\n");
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
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

    if (findUnionLocal(locals.union_locals.items, name)) |union_local| {
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

    const ty = findLocalType(locals.locals.items, name) orelse return null;
    if (!is_managed_local_type(ty, ctx)) return null;
    if (is_union_payload_local_name(locals.union_locals.items, name)) return name;
    return find_local_name(locals.locals.items, name);
}

pub fn emit_overwrite_release_managed_local(allocator: std.mem.Allocator, name: []const u8, out: *std.ArrayList(u8)) !void {
    try appendFmt(allocator, out, "    ;; arc-overwrite-release {s}\n", .{name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
}

pub fn union_payload_local_name_from_locals(
    locals: []const Local,
    base: []const u8,
    idx: usize,
) ?[]const u8 {
    var suffix_buf: [32]u8 = undefined;
    const suffix = std.fmt.bufPrint(&suffix_buf, ".__union_payload_{d}", .{idx}) catch return null;
    for (locals) |local| {
        if (local.name.len != base.len + suffix.len) continue;
        if (!std.mem.startsWith(u8, local.name, base)) continue;
        if (!std.mem.eql(u8, local.name[base.len..], suffix)) continue;
        return local.name;
    }
    return null;
}

pub fn is_union_payload_local_name(union_locals: []const UnionLocal, name: []const u8) bool {
    for (union_locals) |union_local| {
        for (union_local.layout.payload_tys, 0..) |_, idx| {
            var suffix_buf: [32]u8 = undefined;
            const suffix = std.fmt.bufPrint(&suffix_buf, ".__union_payload_{d}", .{idx}) catch return false;
            if (name.len != union_local.name.len + suffix.len) continue;
            if (!std.mem.startsWith(u8, name, union_local.name)) continue;
            if (!std.mem.eql(u8, name[union_local.name.len..], suffix)) continue;
            return true;
        }
    }
    return false;
}

pub fn find_local_name(locals: []const Local, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.name;
    }
    return null;
}

pub fn emit_storage_set_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage = find_storage_primitive_local(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const index_start = first_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    if (index_end >= end_idx or !tokEq(tokens[index_end], ",")) return false;

    const value_start = index_end + 1;
    const value_end = findArgEnd(tokens, value_start, end_idx);
    if (value_end != end_idx) return false;

    if (is_managed_local_type(storage.elem_ty, ctx)) {
        return try emit_storage_set_managed_call(allocator, tokens, index_start, index_end, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) {
        return try emit_storage_set_scalar_call(allocator, tokens, index_start, index_end, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }

    try emit_storage_alias_protect(allocator, out, tokens[start_idx].lexeme, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tokens[start_idx].lexeme});
    if (!try codegen_callbacks.emit_expr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, "u8", out)) return false;
    try out.appendSlice(allocator, "    call $__storage_set_u8\n");
    try emit_storage_alias_release(allocator, out, tokens[start_idx].lexeme, target_name);
    return true;
}

pub fn emit_storage_put_one_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (is_managed_local_type(elem_ty, ctx)) {
        return try emit_storage_put_managed_call(allocator, tokens, value_start, value_end, source_name, target_name, elem_ty, locals, ctx, out);
    }
    if (!std.mem.eql(u8, elem_ty, "u8")) {
        return try emit_storage_put_scalar_call(allocator, tokens, value_start, value_end, source_name, target_name, elem_ty, locals, ctx, out);
    }

    try emit_storage_alias_protect(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, "u8", out)) return false;
    try out.appendSlice(allocator, "    call $__storage_put_u8\n");
    try emit_storage_alias_release(allocator, out, source_name, target_name);
    return true;
}

pub fn emit_storage_set_managed_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, index_start: usize, index_end: usize, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    try out.appendSlice(allocator, "    ;; storage-set-managed\n");
    try emit_storage_alias_protect(allocator, out, source_name, target_name);
    if (!try codegen_callbacks.emit_expr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    call $__storage_check_range\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try emit_storage_clone_managed_current_len(allocator, out, source_name);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emit_storage_element_ptr_from_local(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    ;; storage-managed-overwrite-dec\n");
    try out.appendSlice(allocator, "    call $__arc_dec\n");
    try emit_storage_element_ptr_from_local(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    if (!try emit_managed_storage_value(allocator, tokens, value_start, value_end, elem_ty, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_alias_release(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emit_storage_put_managed_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    try out.appendSlice(allocator, "    ;; storage-put-managed\n");
    try emit_storage_alias_protect(allocator, out, source_name, target_name);
    try emit_storage_len_ptr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emit_storage_cap_ptr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.lt_u\n");
    try out.appendSlice(allocator, "    i32.and\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "      i32.const 1\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emit_storage_clone_managed_with_len_local(allocator, out, source_name, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
    try emit_storage_element_ptr_from_local(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    if (!try emit_managed_storage_value(allocator, tokens, value_start, value_end, elem_ty, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_len_ptr(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.add\n");
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_alias_release(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
    return true;
}

pub fn emit_managed_storage_value(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!try codegen_callbacks.emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, elem_ty, out)) return false;
    if (is_direct_managed_local_expr(tokens, start_idx, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    ;; storage-managed-write-inc\n");
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}
