//! Body-local / loop / multi-result local collection (extracted from gen_expr).
const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_collect = @import("gen_collect.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const gen_hooks = @import("gen_hooks.zig");
const gen_storage = @import("gen_storage.zig");
const gen_struct = @import("gen_struct.zig");
const gen_union_emit = @import("gen_union_emit.zig");
const gen_ctrl = @import("gen_ctrl.zig");
const gen_ownership = @import("gen_ownership.zig");
const gen_host = @import("gen_host.zig");
const gen_wasi = @import("codegen_wasi_registry.zig");
const gen_union = @import("codegen_union_layout.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");

const appendLoopSourceStorageLocal = gen_types.appendLoopSourceStorageLocal;
const parseUnionTypeLayout = gen_collect.parseUnionTypeLayout;
const InferredUnionBinding = gen_types.InferredUnionBinding;
const findUnionLocalExact = gen_types.findUnionLocalExact;
const MultiResultLhs = gen_types.MultiResultLhs;
const SourceOrigin = gen_types.SourceOrigin;
const findPayloadEnumDecl = gen_import.findPayloadEnumDecl;
const tokEq = gen_util.tokEq;
const findMatchingInRange = gen_util.findMatchingInRange;
const findTopLevelToken = gen_util.findTopLevelToken;
const findArgEnd = gen_util.findArgEnd;
const trimParens = gen_util.trimParens;
const publicDeclName = gen_util.publicDeclName;
const appendFmt = gen_util.appendFmt;
const findTopLevelBlockOpen = gen_util.findTopLevelBlockOpen;
const findStmtEnd = gen_util.findStmtEnd;
const LocalSet = gen_types.LocalSet;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const StructLocal = gen_types.StructLocal;
const StorageLocal = gen_types.StorageLocal;
const FuncDecl = gen_types.FuncDecl;
const FuncResultItem = gen_types.FuncResultItem;
const StructDecl = gen_types.StructDecl;
const FieldReflectionLoopHeader = gen_types.FieldReflectionLoopHeader;
const CallbackBinding = gen_types.CallbackBinding;
const CallbackCallArg = gen_types.CallbackCallArg;
const ExprCallHead = gen_types.ExprCallHead;
const STORAGE_OVERWRITE_TMP_LOCAL = gen_types.STORAGE_OVERWRITE_TMP_LOCAL;
const findLocalType = gen_types.findLocalType;
const findStorageLocal = gen_types.findStorageLocal;
const findStructLocal = gen_types.findStructLocal;
const findUnionLocal = gen_types.findUnionLocal;
const hasLocal = gen_types.hasLocal;
const UnionLayout = gen_union.UnionLayout;
const freeUnionLayout = gen_union.freeUnionLayout;
const cloneUnionLayout = gen_union.cloneUnionLayout;
const unionLayoutsEqual = gen_union.unionLayoutsEqual;
const findStructDecl = gen_collect.findStructDecl;
const findStructLayout = gen_collect.findStructLayout;
const pureScalarStructPackWidth = gen_collect.pureScalarStructPackWidth;
const parseCodegenTypeExpr = gen_collect.parseCodegenTypeExpr;
const parseTypeUnionLayoutFromName = gen_collect.parseTypeUnionLayoutFromName;
const substituteGenericTypeOwned = gen_collect.substituteGenericTypeOwned;
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

fn stmtContainsWasiSocketCreate(
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

pub fn emitSelfTailLoopLocalReset(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) !void {
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



pub fn collectBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet) !void {
    try collectBodyLocalsWithMode(allocator, tokens, start_idx, end_idx, ctx, out, true);
}



pub fn multiResultLhsForItem(
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



pub fn collectCallbackCallArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    binding: CallbackBinding) ![]const CallbackCallArg {
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



pub fn funcVariadicParamIndex(func: FuncDecl) ?usize {
    for (func.params, 0..) |param, idx| {
        if (param.variadic) return idx;
    }
    return null;
}






fn appendStructBindingFieldLocals(
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
        try appendLocalField(allocator, out, tokens, ctx, local_name, field.name, field_ty);
    }
}

pub fn collectBodyLocalsWithMode(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
    recurse_nested: bool) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (stmtContainsStringLiteral(tokens, i, stmt_end) or
            stmtContainsFieldNameIntrinsic(tokens, i, stmt_end) or
            stmtContainsStorageAggLiteral(tokens, i, stmt_end) or
            stmtContainsStructLiteralExpr(tokens, i, stmt_end) or
            stmtContainsGetIntrinsic(tokens, i, stmt_end) or
            stmtContainsStorageComparisonIntrinsic(tokens, i, stmt_end) or
            stmtContainsNilComparisonCall(tokens, i, stmt_end) or
            stmtContainsUnionPayloadComparisonCall(tokens, i, stmt_end, out, ctx))
        {
            try out.ensureStorageWriteTemps(allocator);
        }
        if (stmtContainsStructLiteralExpr(tokens, i, stmt_end)) {
            try out.ensureStructLiteralTmp(allocator);
        }
        if (stmtContainsVariadicUserCall(tokens, i, stmt_end, out, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
            try out.ensureVariadicPackTmp(allocator);
        }
        if (stmtContainsNumericSelectIntrinsic(tokens, i, stmt_end)) {
            try out.ensureNumericSelectTemps(allocator);
        }
        if (stmtContainsWasiSocketCreate(tokens, i, stmt_end, ctx)) {
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
        if (recurse_nested and try collectLoopBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Loop block locals collected recursively.
        } else if (recurse_nested and try collectIfBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Block locals collected recursively.
        } else if (recurse_nested and try collectDeferBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Cleanup block locals collected recursively.
        } else if (try typedUnionBindingLayout(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |layout| {
            defer freeUnionLayout(allocator, layout);
            const local_layout = try cloneUnionLayout(allocator, layout);
            try out.appendUnionLocal(allocator, tokens[i].lexeme, local_layout, true, true);
        } else if (try inferredUnionCallBinding(allocator, tokens, i, stmt_end, out, ctx, &out.owned_names)) |binding| {
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
            try appendStructBindingFieldLocals(allocator, tokens, ctx, out, local_name, decl.name, decl, false);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and
            findStructLocal(out.struct_locals.items, tokens[i].lexeme) == null and
            inferredStructBinding(tokens, i, stmt_end, out, ctx) != null)
        {
            const binding = inferredStructBinding(tokens, i, stmt_end, out, ctx).?;
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, binding.ty, true);
            try appendStructBindingFieldLocals(allocator, tokens, ctx, out, local_name, binding.ty, binding.decl, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredScalarBindingType(tokens, i, stmt_end, out, ctx) != null) {
            const ty = inferredScalarBindingType(tokens, i, stmt_end, out, ctx).?;
            try out.appendBorrowedLocal(allocator, tokens[i].lexeme, ty, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredManagedPayloadBinding(tokens, i, stmt_end, out, ctx) != null) {
            const binding = inferredManagedPayloadBinding(tokens, i, stmt_end, out, ctx).?;
            if (isTupleTypeName(binding.elem_ty) and tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (try typedManagedPayloadBinding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
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
        } else if (try collectMultiResultAssignmentLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Multi-result inferred locals collected.
        } else if (isManagedLocalAssignmentStmt(tokens, i, stmt_end, out, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
        } else if (multiResultAssignmentNeedsManagedTmp(tokens, i, stmt_end, out, ctx)) {
            if (!hasLocal(out.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
                try out.appendBorrowedLocal(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
            }
        } else if (try typedStructBinding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, binding.ty, true);
            try appendStructBindingFieldLocals(allocator, tokens, ctx, out, local_name, binding.ty, binding.decl, true);
        } else if (try typedTupleBindingType(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |tuple_ty| {
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, tuple_ty, true);
            try appendTupleLocalFields(allocator, out, tokens, ctx, local_name, tuple_ty);
        }
        i = stmt_end;
    }
}


// --- helpers relocated from gen_lower (domain split) ---


pub fn stmtContainsVariadicUserCall(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (call_head.is_intrinsic) continue;
        const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse {
            i = call_head.args_end;
            continue;
        };
        if (funcHasVariadicParam(func)) return true;
        i = call_head.args_end;
    }
    return false;
}



pub fn stmtContainsNilComparisonCall(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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



pub fn stmtContainsUnionPayloadComparisonCall(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext) bool {
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



pub fn appendLoopValueLocal(
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
        try appendTupleLocalFields(allocator, out, tokens, ctx, local_name, elem_ty);
        try out.ensureTuplePackTemps(allocator);
        return;
    }
    try out.appendBorrowedLocalWithOrigin(allocator, value_name, elem_ty, true, origin);
}


pub fn collectCollectionLoopLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    header: anytype,
    ctx: CodegenContext,
    out: *LocalSet,
) !void {
    try appendLoopIndexLocal(allocator, out, start_idx);
    if (header.source_is_expr) {
        try appendLoopSourceStorageLocal(allocator, out, start_idx, header.source_ty, header.elem_ty);
    }
    if (isManagedLocalType(header.elem_ty, ctx)) {
        try out.ensureStorageWriteTemps(allocator);
    }
    if (header.value_name) |value_name| {
        try appendLoopValueLocal(allocator, out, tokens, ctx, value_name, header.elem_ty, .collection_value);
    }
    if (header.index_name) |index_name| {
        if (!hasLocal(out.locals.items, index_name)) {
            try out.appendBorrowedLocal(allocator, index_name, "usize", true);
        }
    }
}


pub fn collectRecvLoopLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    header: anytype,
    ctx: CodegenContext,
    out: *LocalSet,
) !void {
    try appendLoopCountLocal(allocator, out, start_idx);
    if (isManagedLocalType(header.elem_ty, ctx)) {
        try out.ensureStorageWriteTemps(allocator);
    }
    if (header.value_name) |value_name| {
        try appendLoopValueLocal(allocator, out, tokens, ctx, value_name, header.elem_ty, .recv_value);
    }
    if (header.count_name) |count_name| {
        if (!hasLocal(out.locals.items, count_name)) {
            try out.appendBorrowedLocal(allocator, count_name, "usize", true);
        }
    }
}


pub fn collectLoopBlockLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "loop")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    if (fieldReflectionLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collectFieldReflectionLoopLocals(allocator, tokens, header, ctx, out);
        return true;
    }
    if (collectionLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collectCollectionLoopLocals(allocator, tokens, start_idx, header, ctx, out);
    } else if (recvLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collectRecvLoopLocals(allocator, tokens, start_idx, header, ctx, out);
    }

    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, out);
    return true;
}



pub fn collectFieldReflectionLoopLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    header: FieldReflectionLoopHeader,
    ctx: CodegenContext,
    out: *LocalSet) CodegenError!void {
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
        try appendDeclOnlyLocals(allocator, out, &field_locals);
        visible_index += 1;
    }
}



pub fn appendLoopIndexLocal(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    loop_id: usize) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_index_{d}", .{loop_id});
    if (hasLocal(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.appendOwnedLocalWithOrigin(allocator, name, "usize", .compiler_temp);
}



pub fn appendLoopCountLocal(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    loop_id: usize) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_count_{d}", .{loop_id});
    if (hasLocal(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.appendOwnedLocalWithOrigin(allocator, name, "usize", .compiler_temp);
}



pub fn collectIfBlockLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet) CodegenError!bool {
    if (start_idx + 4 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, out);

    if (close_brace + 1 == end_idx) return true;
    if (close_brace + 1 >= end_idx or !tokEq(tokens[close_brace + 1], "else")) return false;
    if (close_brace + 2 >= end_idx) return false;

    if (tokEq(tokens[close_brace + 2], "if")) {
        _ = try collectIfBlockLocals(allocator, tokens, close_brace + 2, end_idx, ctx, out);
        return true;
    }
    if (!tokEq(tokens[close_brace + 2], "{")) return false;
    const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return false;
    if (close_else + 1 != end_idx) return false;
    try collectBodyLocals(allocator, tokens, close_brace + 3, close_else, ctx, out);
    return true;
}



pub fn collectDeferBlockLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet) CodegenError!bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "defer")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collectBodyLocals(allocator, tokens, start_idx + 2, close_brace, ctx, &cleanup_locals);
    try appendDeclOnlyLocals(allocator, out, &cleanup_locals);
    return true;
}



pub fn appendDeclOnlyLocals(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    source: *const LocalSet) !void {
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
        if (findStorageLocalExact(out.storage_locals.items, storage.name) != null) continue;
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
        if (findStructLocalExact(out.struct_locals.items, struct_local.name) != null) continue;
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



pub fn appendLocalField(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    base: []const u8,
    field: []const u8,
    ty: []const u8) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    if (isTupleTypeName(ty)) {
        try out.owned_names.append(allocator, name);
        const local_name = try out.appendStructLocal(allocator, name, ty, true);
        try appendTupleLocalFields(allocator, out, tokens, ctx, local_name, ty);
        return;
    }
    // Pure-scalar unmanaged struct slot (e.g. Tuple.0 : Point) — nested field locals, not a single i32.
    if (findStructDecl(ctx.structs, ty)) |decl| {
        if (findStructLayout(ctx.struct_layouts, ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
            try out.owned_names.append(allocator, name);
            const local_name = try out.appendStructLocal(allocator, name, ty, true);
            for (decl.fields) |sf| {
                const field_ty = try substituteStructFieldType(allocator, decl, ty, sf.ty, &out.owned_names);
                try appendLocalField(allocator, out, tokens, ctx, local_name, sf.name, field_ty);
            }
            return;
        }
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, &out.owned_names)) |layout| {
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



pub fn stmtContainsStringLiteral(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .string) continue;
        if (tokens[i].lexeme.len < 2 or tokens[i].lexeme[0] != '"') continue;
        return true;
    }
    return false;
}



pub fn stmtContainsStorageComparisonIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        const name = tokens[i + 1].lexeme;
        if (std.mem.eql(u8, name, "eq") or std.mem.eql(u8, name, "ne")) return true;
    }
    return false;
}



pub fn stmtContainsFieldNameIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "field_name")) return true;
    }
    return false;
}



pub fn stmtContainsGetIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "get") or
            std.mem.eql(u8, tokens[i + 1].lexeme, "field_get")) return true;
    }
    return false;
}



pub fn stmtContainsNumericSelectIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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



pub fn typedUnionBindingLayout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8)) CodegenError!?UnionLayout {
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



pub fn inferredUnionCallBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8)) CodegenError!?InferredUnionBinding {
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



pub fn appendTupleLocalFields(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    base: []const u8,
    tuple_ty: []const u8) CodegenError!void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        var field_buf: [32]u8 = undefined;
        const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{idx});
        try appendLocalField(allocator, out, tokens, ctx, base, field_name, elem_ty);
    }
}



pub fn funcHasVariadicParam(func: FuncDecl) bool {
    return funcVariadicParamIndex(func) != null;
}



pub fn findStorageLocalExact(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}



pub fn findStructLocalExact(locals: []const StructLocal, name: []const u8) ?StructLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

// --- more helpers from gen_lower ---


pub fn inferredManagedPayloadBinding(
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



pub fn typedManagedPayloadBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8)) CodegenError!?ManagedPayloadBinding {
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
fn collectOneMultiResultLhsLocal(
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

pub fn collectMultiResultAssignmentLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet) CodegenError!bool {
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
        try collectOneMultiResultLhsLocal(allocator, tokens[lhs_start].lexeme, func.result_items[item_idx], ctx, out);

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (item_idx != func.result_items.len) return error.NoMatchingCall;
    return true;
}



pub fn multiResultAssignmentNeedsManagedTmp(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext) bool {
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
        const lhs = multiResultLhsForItem(tokens[lhs_start].lexeme, func.result_items[item_idx], locals, ctx) orelse return false;
        if (lhs.kind == .managed) return true;

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    return false;
}



pub fn typedTupleBindingType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
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

