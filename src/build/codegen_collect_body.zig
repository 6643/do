//! Body-local / loop / multi-result local collection (extracted from gen_expr).
const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const gen_hooks = @import("gen_hooks.zig");
const gen_storage = @import("gen_storage.zig");
const gen_struct = @import("gen_struct.zig");
const gen_union_emit = @import("gen_union_emit.zig");
const gen_ctrl = @import("gen_ctrl.zig");
const gen_ownership = @import("gen_ownership.zig");
const gen_host = @import("gen_host.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");

const appendLoopSourceStorageLocal = context.appendLoopSourceStorageLocal;
const parseUnionTypeLayout = gen_collect_util.parseUnionTypeLayout;
const InferredUnionBinding = model.InferredUnionBinding;
const findUnionLocalExact = context.findUnionLocalExact;
const MultiResultLhs = model.MultiResultLhs;
const SourceOrigin = model.SourceOrigin;
const findPayloadEnumDecl = gen_import.findPayloadEnumDecl;
const tokEq = codegen_tokens.tok_eq;
const findMatchingInRange = codegen_tokens.find_matching_in_range;
const findTopLevelToken = codegen_tokens.find_top_level_token;
const findArgEnd = codegen_tokens.find_arg_end;
const trimParens = codegen_tokens.trim_parens;
const publicDeclName = codegen_names.public_decl_name;
const appendFmt = codegen_names.append_fmt;
const findTopLevelBlockOpen = codegen_tokens.find_top_level_block_open;
const findStmtEnd = codegen_tokens.find_stmt_end;
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
const findLocalType = context.findLocalType;
const findStorageLocal = context.findStorageLocal;
const findStructLocal = context.findStructLocal;
const findUnionLocal = context.findUnionLocal;
const hasLocal = context.hasLocal;
const UnionLayout = codegen_union_layout.UnionLayout;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const cloneUnionLayout = codegen_union_layout.clone_union_layout;
const unionLayoutsEqual = codegen_union_layout.union_layouts_equal;
const findStructDecl = gen_collect_util.findStructDecl;
const findStructLayout = gen_collect_util.findStructLayout;
const pureScalarStructPackWidth = gen_collect_util.pureScalarStructPackWidth;
const parseCodegenTypeExpr = gen_collect_util.parseCodegenTypeExpr;
const parse_type_union_layout_from_name = codegen_collect_structs.parse_type_union_layout_from_name;
const substituteGenericTypeOwned = gen_collect_util.substituteGenericTypeOwned;
const callHeadAt = gen_import.callHeadAt;
const exprCallHead = gen_import.exprCallHead;
const importedAliasContextForTokens = gen_import.importedAliasContextForTokens;
const isManagedLocalType = gen_wasi_emit.isManagedLocalType;
const isTupleTypeName = gen_wasi_emit.isTupleTypeName;
const tupleArity = gen_wasi_emit.tupleArity;
const tupleElementTypeAt = gen_wasi_emit.tupleElementTypeAt;
const tupleScalarLeafStorageByteWidthCtx = gen_wasi_emit.tupleScalarLeafStorageByteWidthCtx;
const ManagedPayloadBinding = gen_storage.ManagedPayloadBinding;
const stmtContainsStorageAggLiteral = gen_storage.stmtContainsStorageAggLiteral;
const findLocalName = gen_storage.findLocalName;
const inferExprType = gen_storage.inferExprType;
const findFuncDeclForCallHead = gen_storage.findFuncDeclForCallHead;
const substituteStructFieldType = gen_storage.substituteStructFieldType;
const managedPayloadElemTypeFromName = gen_storage.managedPayloadElemTypeFromName;
const emitZeroValueForType = gen_struct.emitZeroValueForType;
const stmtContainsStructLiteralExpr = gen_struct.stmtContainsStructLiteralExpr;
const fieldVisibleFromTokens = gen_struct.fieldVisibleFromTokens;
const fieldReflectionLocalNamePrefix = gen_struct.fieldReflectionLocalNamePrefix;
const unionPayloadComparisonCallBranch = gen_union_emit.unionPayloadComparisonCallBranch;
const buildPayloadEnumUnionLayout = gen_union_emit.buildPayloadEnumUnionLayout;
const fieldReflectionLoopHeader = gen_ctrl.fieldReflectionLoopHeader;
const isDiscardAssignment = gen_ctrl.isDiscardAssignment;
const collectionLoopHeader = gen_ctrl.collectionLoopHeader;
const recvLoopHeader = gen_ctrl.recvLoopHeader;
const isDeadManagedAliasBinding = gen_ctrl.isDeadManagedAliasBinding;
const typedScalarBindingType = gen_ctrl.typedScalarBindingType;
const inferredStructCtorBinding = gen_ctrl.inferredStructCtorBinding;
const inferredScalarBindingType = gen_ctrl.inferredScalarBindingType;
const isManagedLocalAssignmentStmt = gen_ctrl.isManagedLocalAssignmentStmt;
const isCodegenScalarType = gen_union_emit.isCodegenScalarType;
const borrowedFieldMetaLocalSet = gen_struct.borrowedFieldMetaLocalSet;
const collectFieldReflectionBodyLocals = gen_struct.collectFieldReflectionBodyLocals;
const inferredStructBinding = gen_struct.inferredStructBinding;
const typedStructBinding = gen_struct.typedStructBinding;
const appendTypedLocalWithDecl = gen_storage.appendTypedLocalWithDecl;
const appendManagedStructFieldMetaLocal = gen_storage.appendManagedStructFieldMetaLocal;
const managedPayloadBinding = gen_storage.managedPayloadBinding;
const storageBindingElemType = gen_storage.storageBindingElemType;

fn stmt_contains_wasi_socket_create(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tokEq(tokens[i + 1], "(")) continue;
        const import = gen_import.findWasiHostImportForTokens(ctx, tokens, tokens[i].lexeme) orelse continue;
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
        try emitZeroValueForType(allocator, ctx, out, local.ty);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{local.name});
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
        const union_local = findUnionLocal(locals.union_locals.items, name) orelse return null;
        if (!unionLayoutsEqual(union_local.layout, layout)) return null;
        return .{ .name = union_local.name, .ty = item.ty, .item = item, .kind = .union_value };
    }

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (!std.mem.eql(u8, struct_local.ty, item.ty)) return null;
        if (findStructLayout(ctx.struct_layouts, item.ty) != null) {
            const local_name = findLocalName(locals.locals.items, name) orelse return null;
            const local_ty = findLocalType(locals.locals.items, name) orelse return null;
            if (!std.mem.eql(u8, local_ty, item.ty)) return null;
            if (item.abi_len != 1) return null;
            return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .managed };
        }
        const decl = findStructDecl(ctx.structs, item.ty) orelse return null;
        if (item.abi_len != decl.fields.len) return null;
        return .{ .name = struct_local.name, .ty = item.ty, .item = item, .kind = .unmanaged_struct };
    }

    const local_name = findLocalName(locals.locals.items, name) orelse return null;
    const local_ty = findLocalType(locals.locals.items, name) orelse return null;
    if (!std.mem.eql(u8, local_ty, item.ty)) return null;
    if (item.abi_len != 1) return null;
    if (isManagedLocalType(local_ty, ctx)) {
        return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .managed };
    }
    if (isCodegenScalarType(ctx, local_ty)) {
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
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        const range = trimParens(tokens, arg_start, arg_end);
        const actual_name: ?[]const u8 = if (range.end == range.start + 1 and tokens[range.start].kind == .ident)
            tokens[range.start].lexeme
        else
            null;
        const arg_ty = binding.shape.param_types[idx] orelse inferExprType(tokens, arg_start, arg_end, locals, ctx) orelse return error.NoMatchingCall;
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
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
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
    if (findStructLayout(ctx.struct_layouts, struct_ty) != null) {
        try out.appendBorrowedLocal(allocator, local_name, struct_ty, true);
        for (decl.fields) |field| {
            const field_ty = if (substitute)
                try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &out.owned_names)
            else
                field.ty;
            try appendManagedStructFieldMetaLocal(allocator, out, local_name, field.name, field_ty);
        }
        try out.ensureStorageWriteTemps(allocator);
        return;
    }
    for (decl.fields) |field| {
        const field_ty = if (substitute)
            try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &out.owned_names)
        else
            field.ty;
        try append_local_field(allocator, out, tokens, ctx, local_name, field.name, field_ty);
    }
}

pub fn collect_body_locals_with_mode(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet, recurse_nested: bool) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (stmt_contains_string_literal(tokens, i, stmt_end) or
            stmt_contains_field_name_intrinsic(tokens, i, stmt_end) or
            stmtContainsStorageAggLiteral(tokens, i, stmt_end) or
            stmtContainsStructLiteralExpr(tokens, i, stmt_end) or
            stmt_contains_get_intrinsic(tokens, i, stmt_end) or
            stmt_contains_storage_comparison_intrinsic(tokens, i, stmt_end) or
            stmt_contains_nil_comparison_call(tokens, i, stmt_end) or
            stmt_contains_union_payload_comparison_call(tokens, i, stmt_end, out, ctx))
        {
            try out.ensureStorageWriteTemps(allocator);
        }
        if (stmtContainsStructLiteralExpr(tokens, i, stmt_end)) {
            try out.ensureStructLiteralTmp(allocator);
        }
        if (stmt_contains_variadic_user_call(tokens, i, stmt_end, out, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
            try out.ensureVariadicPackTmp(allocator);
        }
        if (stmt_contains_numeric_select_intrinsic(tokens, i, stmt_end)) {
            try out.ensureNumericSelectTemps(allocator);
        }
        if (stmt_contains_wasi_socket_create(tokens, i, stmt_end, ctx)) {
            try out.ensureWasiFamilyTmp(allocator);
        }
        if (isDiscardAssignment(tokens, i, stmt_end)) {
            i = stmt_end;
            continue;
        }
        if (try isDeadManagedAliasBinding(allocator, tokens, i, stmt_end, end_idx, out, ctx)) {
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
            try out.appendUnionLocal(allocator, tokens[i].lexeme, local_layout, true, true);
        } else if (try inferred_union_call_binding(allocator, tokens, i, stmt_end, out, ctx, &out.owned_names)) |binding| {
            errdefer if (binding.owns_layout) freeUnionLayout(allocator, binding.layout);
            try out.appendUnionLocal(allocator, tokens[i].lexeme, binding.layout, true, binding.owns_layout);
        } else if (typedScalarBindingType(tokens, i, stmt_end, ctx)) |ty| {
            try out.appendBorrowedLocal(allocator, tokens[i].lexeme, ty, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and
            findStructLocal(out.struct_locals.items, tokens[i].lexeme) == null and
            inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs) != null)
        {
            // Unmanaged pure-scalar structs live in struct_locals + field slots (`out.n`),
            // not as a single `out` scalar local. Reassignment (e.g. `out = @field_set(...)`)
            // must not invent a field-reflection-scoped shadow binding.
            const decl = inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs).?;
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, decl.name, true);
            try append_struct_binding_field_locals(allocator, tokens, ctx, out, local_name, decl.name, decl, false);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and
            findStructLocal(out.struct_locals.items, tokens[i].lexeme) == null and
            inferredStructBinding(tokens, i, stmt_end, out, ctx) != null)
        {
            const binding = inferredStructBinding(tokens, i, stmt_end, out, ctx).?;
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, binding.ty, true);
            try append_struct_binding_field_locals(allocator, tokens, ctx, out, local_name, binding.ty, binding.decl, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredScalarBindingType(tokens, i, stmt_end, out, ctx) != null) {
            const ty = inferredScalarBindingType(tokens, i, stmt_end, out, ctx).?;
            try out.appendBorrowedLocal(allocator, tokens[i].lexeme, ty, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferred_managed_payload_binding(tokens, i, stmt_end, out, ctx) != null) {
            const binding = inferred_managed_payload_binding(tokens, i, stmt_end, out, ctx).?;
            if (isTupleTypeName(binding.elem_ty) and tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (try typed_managed_payload_binding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
            if (isTupleTypeName(binding.elem_ty) and tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (managedPayloadBinding(tokens, i, stmt_end)) |binding| {
            if (isTupleTypeName(binding.elem_ty) and tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (storageBindingElemType(tokens, i, stmt_end)) |raw_elem_ty| {
            const elem_ty = try substituteGenericTypeOwned(allocator, raw_elem_ty, ctx.type_bindings, &out.owned_names);
            // Scheme A: scalar + managed handle + pure-scalar nested struct slots.
            if (isTupleTypeName(elem_ty) and tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocal(allocator, tokens[i].lexeme, elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (try collect_multi_result_assignment_locals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Multi-result inferred locals collected.
        } else if (isManagedLocalAssignmentStmt(tokens, i, stmt_end, out, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
        } else if (multi_result_assignment_needs_managed_tmp(tokens, i, stmt_end, out, ctx)) {
            if (!hasLocal(out.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
                try out.appendBorrowedLocal(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
            }
        } else if (try typedStructBinding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, binding.ty, true);
            try append_struct_binding_field_locals(allocator, tokens, ctx, out, local_name, binding.ty, binding.decl, true);
        } else if (try typed_tuple_binding_type(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |tuple_ty| {
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, tuple_ty, true);
            try append_tuple_local_fields(allocator, out, tokens, ctx, local_name, tuple_ty);
        }
        i = stmt_end;
    }
}

// --- helpers relocated from gen_lower (domain split) ---

pub fn stmt_contains_variadic_user_call(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (call_head.is_intrinsic) continue;
        const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse {
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
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (!call_head.is_intrinsic) {
            i = call_head.args_end;
            continue;
        }
        const call_name = tokens[call_head.name_idx].lexeme;
        if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) {
            i = call_head.args_end;
            continue;
        }
        const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (first_end == call_head.args_start or first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) {
            i = call_head.args_end;
            continue;
        }
        const second_start = first_end + 1;
        const second_end = findArgEnd(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) {
            i = call_head.args_end;
            continue;
        }
        const first_nil = first_end == call_head.args_start + 1 and tokEq(tokens[call_head.args_start], "nil");
        const second_nil = second_end == second_start + 1 and tokEq(tokens[second_start], "nil");
        if (first_nil or second_nil) return true;
        i = call_head.args_end;
    }
    return false;
}

pub fn stmt_contains_union_payload_comparison_call(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (!call_head.is_intrinsic) {
            i = call_head.args_end;
            continue;
        }
        const call_name = tokens[call_head.name_idx].lexeme;
        if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) {
            i = call_head.args_end;
            continue;
        }
        if (unionPayloadComparisonCallBranch(tokens, call_head.args_start, call_head.args_end, locals, ctx) != null) return true;
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
    if (hasLocal(out.locals.items, value_name)) return;
    if (isTupleTypeName(elem_ty)) {
        const local_name = try out.appendStructLocalWithOrigin(allocator, value_name, elem_ty, true, origin);
        try append_tuple_local_fields(allocator, out, tokens, ctx, local_name, elem_ty);
        try out.ensureTuplePackTemps(allocator);
        return;
    }
    try out.appendBorrowedLocalWithOrigin(allocator, value_name, elem_ty, true, origin);
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
        try appendLoopSourceStorageLocal(allocator, out, start_idx, header.source_ty, header.elem_ty);
    }
    if (isManagedLocalType(header.elem_ty, ctx)) {
        try out.ensureStorageWriteTemps(allocator);
    }
    if (header.value_name) |value_name| {
        try append_loop_value_local(allocator, out, tokens, ctx, value_name, header.elem_ty, .collection_value);
    }
    if (header.index_name) |index_name| {
        if (!hasLocal(out.locals.items, index_name)) {
            try out.appendBorrowedLocal(allocator, index_name, "usize", true);
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
    if (isManagedLocalType(header.elem_ty, ctx)) {
        try out.ensureStorageWriteTemps(allocator);
    }
    if (header.value_name) |value_name| {
        try append_loop_value_local(allocator, out, tokens, ctx, value_name, header.elem_ty, .recv_value);
    }
    if (header.count_name) |count_name| {
        if (!hasLocal(out.locals.items, count_name)) {
            try out.appendBorrowedLocal(allocator, count_name, "usize", true);
        }
    }
}

pub fn collect_loop_block_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "loop")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    if (fieldReflectionLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collect_field_reflection_loop_locals(allocator, tokens, header, ctx, out);
        return true;
    }
    if (collectionLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collect_collection_loop_locals(allocator, tokens, start_idx, header, ctx, out);
    } else if (recvLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collect_recv_loop_locals(allocator, tokens, start_idx, header, ctx, out);
    }

    try collect_body_locals(allocator, tokens, open_brace + 1, close_brace, ctx, out);
    return true;
}

pub fn collect_field_reflection_loop_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, header: FieldReflectionLoopHeader, ctx: CodegenContext, out: *LocalSet) CodegenError!void {
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!fieldVisibleFromTokens(field, header.decl, tokens)) continue;
        const prefix = try fieldReflectionLocalNamePrefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        var field_locals = try borrowedFieldMetaLocalSet(allocator, out, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collectFieldReflectionBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &field_locals);
        try append_decl_only_locals(allocator, out, &field_locals);
        visible_index += 1;
    }
}

pub fn append_loop_index_local(allocator: std.mem.Allocator, out: *LocalSet, loop_id: usize) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_index_{d}", .{loop_id});
    if (hasLocal(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.appendOwnedLocalWithOrigin(allocator, name, "usize", .compiler_temp);
}

pub fn append_loop_count_local(allocator: std.mem.Allocator, out: *LocalSet, loop_id: usize) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_count_{d}", .{loop_id});
    if (hasLocal(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.appendOwnedLocalWithOrigin(allocator, name, "usize", .compiler_temp);
}

pub fn collect_if_block_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    if (start_idx + 4 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    try collect_body_locals(allocator, tokens, open_brace + 1, close_brace, ctx, out);

    if (close_brace + 1 == end_idx) return true;
    if (close_brace + 1 >= end_idx or !tokEq(tokens[close_brace + 1], "else")) return false;
    if (close_brace + 2 >= end_idx) return false;

    if (tokEq(tokens[close_brace + 2], "if")) {
        _ = try collect_if_block_locals(allocator, tokens, close_brace + 2, end_idx, ctx, out);
        return true;
    }
    if (!tokEq(tokens[close_brace + 2], "{")) return false;
    const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return false;
    if (close_else + 1 != end_idx) return false;
    try collect_body_locals(allocator, tokens, close_brace + 3, close_else, ctx, out);
    return true;
}

pub fn collect_defer_block_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "defer")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collect_body_locals(allocator, tokens, start_idx + 2, close_brace, ctx, &cleanup_locals);
    try append_decl_only_locals(allocator, out, &cleanup_locals);
    return true;
}

pub fn append_decl_only_locals(allocator: std.mem.Allocator, out: *LocalSet, source: *const LocalSet) !void {
    for (source.locals.items) |local| {
        if (hasLocal(out.locals.items, local.name)) continue;
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
        if (findUnionLocalExact(out.union_locals.items, union_local.name) != null) continue;
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
    if (isTupleTypeName(ty)) {
        try out.owned_names.append(allocator, name);
        const local_name = try out.appendStructLocal(allocator, name, ty, true);
        try append_tuple_local_fields(allocator, out, tokens, ctx, local_name, ty);
        return;
    }
    // Pure-scalar unmanaged struct slot (e.g. Tuple.0 : Point) — nested field locals, not a single i32.
    if (findStructDecl(ctx.structs, ty)) |decl| {
        if (findStructLayout(ctx.struct_layouts, ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
            try out.owned_names.append(allocator, name);
            const local_name = try out.appendStructLocal(allocator, name, ty, true);
            for (decl.fields) |sf| {
                const field_ty = try substituteStructFieldType(allocator, decl, ty, sf.ty, &out.owned_names);
                try append_local_field(allocator, out, tokens, ctx, local_name, sf.name, field_ty);
            }
            return;
        }
    }
    if (try parse_type_union_layout_from_name(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, &out.owned_names)) |layout| {
        errdefer freeUnionLayout(allocator, layout);
        const exists = findUnionLocalExact(out.union_locals.items, name) != null;
        if (!exists) {
            errdefer allocator.free(name);
            try out.owned_names.append(allocator, name);
            errdefer _ = out.owned_names.pop();
        } else {
            defer allocator.free(name);
        }
        return out.appendUnionLocal(allocator, name, layout, true, true);
    }
    // Named payload enum type on field/local path
    if (findPayloadEnumDecl(ctx.payload_enums, ty)) |decl| {
        const layout = try buildPayloadEnumUnionLayout(allocator, decl, tokens, ctx.structs, ctx.struct_layouts, &out.owned_names);
        errdefer freeUnionLayout(allocator, layout);
        const exists = findUnionLocalExact(out.union_locals.items, name) != null;
        if (!exists) {
            errdefer allocator.free(name);
            try out.owned_names.append(allocator, name);
            errdefer _ = out.owned_names.pop();
        } else {
            defer allocator.free(name);
        }
        return out.appendUnionLocal(allocator, name, layout, true, true);
    }
    try out.appendOwnedLocal(allocator, name, ty);
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
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        const name = tokens[i + 1].lexeme;
        if (std.mem.eql(u8, name, "eq") or std.mem.eql(u8, name, "ne")) return true;
    }
    return false;
}

pub fn stmt_contains_field_name_intrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "field_name")) return true;
    }
    return false;
}

pub fn stmt_contains_get_intrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "get") or
            std.mem.eql(u8, tokens[i + 1].lexeme, "field_get")) return true;
    }
    return false;
}

pub fn stmt_contains_numeric_select_intrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
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
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    // Named payload enum: `m Message = …`
    if (eq_idx == start_idx + 2 and tokens[start_idx + 1].kind == .ident) {
        const ty_name = publicDeclName(tokens[start_idx + 1].lexeme);
        if (findPayloadEnumDecl(ctx.payload_enums, ty_name)) |decl| {
            return try buildPayloadEnumUnionLayout(allocator, decl, tokens, ctx.structs, ctx.struct_layouts, owned_types);
        }
    }
    return try parseUnionTypeLayout(
        allocator,
        tokens,
        start_idx + 1,
        eq_idx,
        ctx.structs,
        ctx.struct_layouts,
        importedAliasContextForTokens(ctx.imported_alias_ctx, tokens),
        owned_types,
    );
}

pub fn inferred_union_call_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?InferredUnionBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const range = trimParens(tokens, start_idx + 2, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| {
        if (func.result_union) |layout| {
            return .{ .layout = layout, .owns_layout = false };
        }
        return null;
    }
    if (gen_hooks.infer_generic_call_union_result) |infer_fn| {
        if (try infer_fn(allocator, tokens, call_head, locals, ctx, owned_types)) |layout| {
            return .{ .layout = layout, .owns_layout = true };
        }
    }
    return null;
}

pub fn append_tuple_local_fields(allocator: std.mem.Allocator, out: *LocalSet, tokens: []const lexer.Token, ctx: CodegenContext, base: []const u8, tuple_ty: []const u8) CodegenError!void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
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

// --- more helpers from gen_lower ---

pub fn inferred_managed_payload_binding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?ManagedPayloadBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const ty = inferExprType(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    const elem_ty = managedPayloadElemTypeFromName(ty) orelse return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

pub fn typed_managed_payload_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?ManagedPayloadBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed = (try parseCodegenTypeExpr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed.next_idx != eq_idx) return null;
    const ty = try substituteGenericTypeOwned(allocator, parsed.ty, ctx.type_bindings, owned_types);
    const elem_ty = managedPayloadElemTypeFromName(ty) orelse return null;
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
        if (findUnionLocal(out.union_locals.items, name) != null) return;
        const cloned = try cloneUnionLayout(allocator, layout);
        try out.appendUnionLocal(allocator, name, cloned, true, true);
        return;
    }
    if (findLocalType(out.locals.items, name) != null) return;
    if (findStructLocal(out.struct_locals.items, name) != null) return;
    if (findStorageLocal(out.storage_locals.items, name) != null) return;
    try appendTypedLocalWithDecl(allocator, out, name, item.ty, ctx, true);
}

pub fn collect_multi_result_assignment_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, out, ctx) orelse return false;
    if (func.results.len <= 1 or func.result_items.len == 0) return false;

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return error.NoMatchingCall;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return error.NoMatchingCall;
        try collect_one_multi_result_lhs_local(allocator, tokens[lhs_start].lexeme, func.result_items[item_idx], ctx, out);

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (item_idx != func.result_items.len) return error.NoMatchingCall;
    return true;
}

pub fn multi_result_assignment_needs_managed_tmp(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len <= 1) return false;
    if (func.result_items.len == 0) return false;

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return false;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return false;
        const lhs = multi_result_lhs_for_item(tokens[lhs_start].lexeme, func.result_items[item_idx], locals, ctx) orelse return false;
        if (lhs.kind == .managed) return true;

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    return false;
}

pub fn typed_tuple_binding_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed_ty.next_idx != eq_idx) return null;
    const ty = try substituteGenericTypeOwned(allocator, parsed_ty.ty, ctx.type_bindings, owned_types);
    if (!isTupleTypeName(ty)) return null;
    return ty;
}
