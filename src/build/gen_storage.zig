//! Storage / tuple emit and pack helpers.

const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const gen_collect = @import("gen_collect.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const gen_hooks = @import("gen_hooks.zig");
const gen_tuple = @import("gen_tuple.zig");
const findValueEnumDeclLineByName = gen_import.findValueEnumDeclLineByName;
const findValueEnumDeclLineByBranch = gen_import.findValueEnumDeclLineByBranch;
const simpleTypeName = gen_collect.simpleTypeName;
const isTopLevelCommaAny = gen_collect.isTopLevelCommaAny;
const isReturnArrowAt = gen_collect.isReturnArrowAt;
const codegen_union_layout = @import("codegen_union_layout.zig");
const gen_host = @import("gen_host.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");

const tokEq = codegen_tokens.tok_eq;
const findMatching = codegen_tokens.find_matching;
const findMatchingInRange = codegen_tokens.find_matching_in_range;
const findLineEnd = codegen_tokens.find_line_end;
const findLineStart = codegen_tokens.find_line_start;
const isLineStart = codegen_tokens.is_line_start;
const findTopLevelToken = codegen_tokens.find_top_level_token;
const findArgEnd = codegen_tokens.find_arg_end;
const trimParens = codegen_tokens.trim_parens;
const publicDeclName = codegen_names.public_decl_name;
const appendFmt = codegen_names.append_fmt;
const Range = codegen_tokens.Range;
const alignUp = codegen_tokens.align_up;
const compactTokenText = codegen_tokens.compact_token_text;
const stringTokenBody = codegen_tokens.string_token_body;
const stringLiteralArgLexeme = codegen_tokens.string_literal_arg_lexeme;
const isStringLiteralArg = codegen_tokens.is_string_literal_arg;
const decodeQuotedStringToken = codegen_tokens.decode_quoted_string_token;
const findToken = codegen_tokens.find_token;
const findTopLevelBlockOpen = codegen_tokens.find_top_level_block_open;
const findStmtEnd = codegen_tokens.find_stmt_end;
const findTypeArgEnd = codegen_tokens.find_type_arg_end;
const moduleTokensEqual = codegen_tokens.module_tokens_equal;
const moduleScopedSymbolName = codegen_names.module_scoped_symbol_name;
const appendMangledTypeName = codegen_names.append_mangled_type_name;
const isUserFuncDeclStart = codegen_tokens.is_user_func_decl_start;
const isPublicTypeName = codegen_names.is_public_type_name;
const isErrorTypeName = codegen_names.is_error_type_name;
const isBaseIntTypeName = codegen_names.is_base_int_type_name;
const isCoreWasmScalar = codegen_names.is_core_wasm_scalar;
const isCoreIntegerScalar = codegen_names.is_core_integer_scalar;
const isCoreFloatScalar = codegen_names.is_core_float_scalar;
const isNumericCoreFuncName = codegen_names.is_numeric_core_func_name;
const isBitwiseCoreFuncName = codegen_names.is_bitwise_core_func_name;
const isCountBitsCoreFuncName = codegen_names.is_count_bits_core_func_name;
const isNumericUnarySelectCoreFuncName = codegen_names.is_numeric_unary_select_core_func_name;
const isNumericBinarySelectCoreFuncName = codegen_names.is_numeric_binary_select_core_func_name;
const isFloatUnaryCoreFuncName = codegen_names.is_float_unary_core_func_name;
const isFloatBinaryCoreFuncName = codegen_names.is_float_binary_core_func_name;
const isBoolSpecialFuncName = codegen_names.is_bool_special_func_name;
const isComparisonCoreFuncName = codegen_names.is_comparison_core_func_name;
const isMemoryLoadName = codegen_names.is_memory_load_name;
const isCoreWasmCallName = codegen_names.is_core_wasm_call_name;
const tokenTextEqualsCompact = codegen_tokens.token_text_equals_compact;
const findTopLevelTypeSeparator = codegen_tokens.find_top_level_type_separator;
const findTopLevelTypeSeparatorFrom = codegen_tokens.find_top_level_type_separator_from;
const hasString = codegen_names.has_string;

const LocalSet = context.LocalSet;
const Local = model.Local;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const StructDecl = model.StructDecl;
const StructField = model.StructField;
const StructLayout = model.StructLayout;
const StructLocal = model.StructLocal;
const StorageLocal = model.StorageLocal;
const UnionLocal = model.UnionLocal;
const FuncDecl = model.FuncDecl;
const FuncParam = model.FuncParam;
const FuncResultItem = model.FuncResultItem;
const HostImport = model.HostImport;
const DeferContext = context.DeferContext;
const CallLastUseMoveContext = context.CallLastUseMoveContext;
const LastUseManagedMoveSource = context.LastUseManagedMoveSource;
const LoopControl = context.LoopControl;
const FieldMetaLocal = model.FieldMetaLocal;
const FieldReflectionLoopHeader = context.FieldReflectionLoopHeader;
const FieldStaticValue = context.FieldStaticValue;
const FieldReflectionIfParts = context.FieldReflectionIfParts;
const GenericTypeBinding = model.GenericTypeBinding;
const PayloadEnumDecl = model.PayloadEnumDecl;
const ValueEnumDecl = model.ValueEnumDecl;
const CallbackBinding = model.CallbackBinding;
const CallbackCallArg = model.CallbackCallArg;
const FuncTypeShape = model.FuncTypeShape;
const LambdaExprShape = model.LambdaExprShape;
const NarrowedUnionLocal = model.NarrowedUnionLocal;
const UnionStructPayload = model.UnionStructPayload;
const ImportedAliasContext = model.ImportedAliasContext;
const StringDataContext = context.StringDataContext;
const ExprCallHead = model.ExprCallHead;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const STORAGE_WRITE_INDEX_TMP_LOCAL = constants.STORAGE_WRITE_INDEX_TMP_LOCAL;
const STORAGE_PUT_SOURCE_TMP_LOCAL = constants.STORAGE_PUT_SOURCE_TMP_LOCAL;
const STORAGE_WRITE_LEN_TMP_LOCAL = constants.STORAGE_WRITE_LEN_TMP_LOCAL;
const STORAGE_WRITE_SCAN_TMP_LOCAL = constants.STORAGE_WRITE_SCAN_TMP_LOCAL;
const STORAGE_WRITE_TARGET_TMP_LOCAL = constants.STORAGE_WRITE_TARGET_TMP_LOCAL;
const STORAGE_WRITE_NEXT_TMP_LOCAL = constants.STORAGE_WRITE_NEXT_TMP_LOCAL;
const TUPLE_PACK_BASE_TMP_LOCAL = constants.TUPLE_PACK_BASE_TMP_LOCAL;
const STRUCT_LITERAL_TMP_LOCAL = constants.STRUCT_LITERAL_TMP_LOCAL;
const STORAGE_PAYLOAD_HEADER_BYTES = constants.STORAGE_PAYLOAD_HEADER_BYTES;
const TYPE_ID_STORAGE_U8 = constants.TYPE_ID_STORAGE_U8;
const TYPE_ID_STORAGE_MANAGED = constants.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_FIRST_STRUCT = constants.TYPE_ID_FIRST_STRUCT;
const findLocalType = context.findLocalType;
const findLocalOrigin = context.findLocalOrigin;
const findStorageLocal = context.findStorageLocal;
const findStructLocal = context.findStructLocal;
const findUnionLocal = context.findUnionLocal;
const hasLocal = context.hasLocal;
const isCompilerLocalName = context.isCompilerLocalName;
const storageTypeNameForElem = context.storageTypeNameForElem;
const storageTypeNameForElemOwned = context.storageTypeNameForElemOwned;
const localNameMatches = context.localNameMatches;
const unionPayloadLocalName = context.unionPayloadLocalName;
const unionTagLocalName = context.unionTagLocalName;

const UnionLayout = codegen_union_layout.UnionLayout;
const UnionBranch = codegen_union_layout.UnionBranch;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const cloneUnionLayout = codegen_union_layout.clone_union_layout;
const unionLayoutsEqual = codegen_union_layout.union_layouts_equal;
const unionBranchIsStatusI32 = codegen_union_layout.union_branch_is_status_i32;

const findStructDecl = gen_collect.findStructDecl;
const findStructLayout = gen_collect.findStructLayout;
const findStructLayoutExact = gen_collect.findStructLayoutExact;
const isPackManagedHandleLeaf = gen_collect.isPackManagedHandleLeaf;
const leafPayloadBytesForPack = gen_collect.leafPayloadBytesForPack;
const pureScalarStructPackWidth = gen_collect.pureScalarStructPackWidth;
const packSlotWidth = gen_collect.packSlotWidth;
const tuplePackWidthWithStructs = gen_collect.tuplePackWidthWithStructs;
const appendTupleLeafTypesWithStructs = gen_collect.appendTupleLeafTypesWithStructs;
const appendTupleLeafTypes = gen_collect.appendTupleLeafTypes;
const structDeclHasManagedField = gen_collect.structDeclHasManagedField;
const ensureStoragePackLayout = gen_collect.ensureStoragePackLayout;
const managedLeafFieldName = gen_collect.managedLeafFieldName;
const isErrorLikeType = gen_collect.isErrorLikeType;
const parseCodegenTypeExpr = gen_collect.parseCodegenTypeExpr;
const parseTypeUnionLayoutFromName = gen_collect.parseTypeUnionLayoutFromName;
const bindStructTypeArgs = gen_collect.bindStructTypeArgs;
const substituteGenericTypeOwned = gen_collect.substituteGenericTypeOwned;
const findGenericBinding = gen_collect.findGenericBinding;
const sameCallableSourceName = gen_collect.sameCallableSourceName;
const funcParamAbiType = gen_collect.funcParamAbiType;
const isUnmanagedScalarStruct = gen_collect.isUnmanagedScalarStruct;
const appendUnionBranchPayloadTypes = gen_collect.appendUnionBranchPayloadTypes;

const callHeadAt = gen_import.callHeadAt;
const exprCallHead = gen_import.exprCallHead;
const callHeadHasTypeArgs = gen_import.callHeadHasTypeArgs;
const findValueEnumDecl = gen_import.findValueEnumDecl;
const findCodegenImportByAlias = gen_import.findCodegenImportByAlias;
const importedAliasContextForTokens = gen_import.importedAliasContextForTokens;
const localScalarConst = gen_import.localScalarConst;
const importedScalarConst = gen_import.importedScalarConst;
const findImportedModuleIndex = gen_import.findImportedModuleIndex;
const findImportedModuleIndexNoAlloc = gen_import.findImportedModuleIndexNoAlloc;
const findWasiHostImportForTokens = gen_import.findWasiHostImportForTokens;
const wasiSourceForTokens = gen_import.wasiSourceForTokens;

const isManagedLocalType = gen_wasi_emit.isManagedLocalType;
const isManagedPayloadType = gen_wasi_emit.isManagedPayloadType;
const isStorageTypeName = gen_wasi_emit.isStorageTypeName;
const storageElemTypeFromName = gen_wasi_emit.storageElemTypeFromName;
const storageElementByteWidth = gen_wasi_emit.storageElementByteWidth;
const storageTypeIdForElement = gen_wasi_emit.storageTypeIdForElement;
const typePayloadBytes = gen_wasi_emit.typePayloadBytes;
const typePayloadAlignment = gen_wasi_emit.typePayloadAlignment;
const isTupleTypeName = gen_wasi_emit.isTupleTypeName;
const tupleArity = gen_wasi_emit.tupleArity;
const tupleElementTypeAt = gen_wasi_emit.tupleElementTypeAt;
const codegenWasmType = gen_wasi_emit.codegenWasmType;
const codegenTypesCompatible = gen_wasi_emit.codegenTypesCompatible;
const findStoragePrimitiveLocal = gen_wasi_emit.findStoragePrimitiveLocal;
const emitReplaceManagedLocalFromTmp = gen_wasi_emit.emitReplaceManagedLocalFromTmp;
const emitStorageDataPtr = gen_wasi_emit.emitStorageDataPtr;
const emitStorageLenPtr = gen_wasi_emit.emitStorageLenPtr;
const appendLoadForPayloadType = gen_wasi_emit.appendLoadForPayloadType;
const structFieldPayloadOffset = gen_wasi_emit.structFieldPayloadOffset;
const findUnionBranchByType = gen_wasi_emit.findUnionBranchByType;
const errorEnumBranchValue = gen_wasi_emit.errorEnumBranchValue;
const tupleScalarLeafStorageByteWidth = gen_wasi_emit.tupleScalarLeafStorageByteWidth;
const tupleScalarLeafStorageByteWidthCtx = gen_wasi_emit.tupleScalarLeafStorageByteWidthCtx;
const tupleHasManagedPackLeaf = gen_wasi_emit.tupleHasManagedPackLeaf;
const tupleHasManagedPackLeafWithStructs = gen_wasi_emit.tupleHasManagedPackLeafWithStructs;
const tupleHasManagedPackLeafCtx = gen_wasi_emit.tupleHasManagedPackLeafCtx;
const emitWasiHostImportExpr = gen_wasi_emit.emitWasiHostImportExpr;
const emitBareWasiHostImportCall = gen_wasi_emit.emitBareWasiHostImportCall;
const emitWasiUnitResultAsUnionValue = gen_wasi_emit.emitWasiUnitResultAsUnionValue;
const emitWasiFilesizeResultAsUnionValue = gen_wasi_emit.emitWasiFilesizeResultAsUnionValue;
const emitWasiReadResultAsUnionValue = gen_wasi_emit.emitWasiReadResultAsUnionValue;
const emitWasiListU8ResultAsUnionValue = gen_wasi_emit.emitWasiListU8ResultAsUnionValue;
const emitWasiDescriptorResultAsUnionValue = gen_wasi_emit.emitWasiDescriptorResultAsUnionValue;
const emitWasiRecordStructBinding = gen_wasi_emit.emitWasiRecordStructBinding;
const isTuplePackableLeafType = type_util.isTuplePackableLeafType;
const isCoreWasmScalar_tu = type_util.isCoreWasmScalar;

const hostParamIsPtrLen = gen_host.hostParamIsPtrLen;
const hostArgCouldBeStoragePtrLenSyntax = gen_host.hostArgCouldBeStoragePtrLenSyntax;
const findHostImportForTokens = gen_host.findHostImportForTokens;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;

// Re-export tuple pack helpers (physical home: gen_tuple.zig).
pub const appendIncManagedTupleLeavesOnStackCtx = gen_tuple.appendIncManagedTupleLeavesOnStackCtx;
pub const appendLoadForPayloadTypeWithIndent = gen_tuple.appendLoadForPayloadTypeWithIndent;
pub const appendLoadTupleElementFromPackedBaseCtx = gen_tuple.appendLoadTupleElementFromPackedBaseCtx;
pub const appendLoadTupleElementOwningFromPackedBase = gen_tuple.appendLoadTupleElementOwningFromPackedBase;
pub const appendLoadTupleLeafTypesOfStructToStack = gen_tuple.appendLoadTupleLeafTypesOfStructToStack;
pub const appendLoadTupleLeavesOwningToStack = gen_tuple.appendLoadTupleLeavesOwningToStack;
pub const appendLoadTupleLeavesOwningToStackCtx = gen_tuple.appendLoadTupleLeavesOwningToStackCtx;
pub const appendLoadTupleScalarLeavesToStack = gen_tuple.appendLoadTupleScalarLeavesToStack;
pub const appendLoadTupleScalarLeavesToStackCtx = gen_tuple.appendLoadTupleScalarLeavesToStackCtx;
pub const appendStoreForPayloadType = gen_tuple.appendStoreForPayloadType;
pub const appendStoreForPayloadTypeWithIndent = gen_tuple.appendStoreForPayloadTypeWithIndent;
pub const appendStoreTupleLeavesOwningFromStack = gen_tuple.appendStoreTupleLeavesOwningFromStack;
pub const appendStoreTupleLeavesOwningFromStackCtx = gen_tuple.appendStoreTupleLeavesOwningFromStackCtx;
pub const appendStoreTupleScalarLeavesFromStack = gen_tuple.appendStoreTupleScalarLeavesFromStack;
pub const appendStoreTupleScalarLeavesFromStackCtx = gen_tuple.appendStoreTupleScalarLeavesFromStackCtx;
pub const emitDecManagedTupleLeavesAtBase = gen_tuple.emitDecManagedTupleLeavesAtBase;
pub const emitIncManagedTupleLeavesAtBase = gen_tuple.emitIncManagedTupleLeavesAtBase;
pub const emitPureScalarStructLocalGet = gen_tuple.emitPureScalarStructLocalGet;
pub const emitPureScalarStructLocalSet = gen_tuple.emitPureScalarStructLocalSet;
pub const emitStorageIncCopiedPackElements = gen_tuple.emitStorageIncCopiedPackElements;
pub const emitTupleGetBinding = gen_tuple.emitTupleGetBinding;
pub const emitTupleLocalGet = gen_tuple.emitTupleLocalGet;
pub const emitTupleLocalSet = gen_tuple.emitTupleLocalSet;
pub const emitTupleReturnLocal = gen_tuple.emitTupleReturnLocal;
pub const singleTupleResultItem = gen_tuple.singleTupleResultItem;
pub const tupleElementPackOffsetWithStructs = gen_tuple.tupleElementPackOffsetWithStructs;
pub const tupleGetElementInfo = gen_tuple.tupleGetElementInfo;
pub const tuplePackSpillLocal = gen_tuple.tuplePackSpillLocal;

pub fn emitStorageBinding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const source_name = tokens[start_idx].lexeme;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    const storage = findStorageLocal(locals.storage_locals.items, source_name) orelse return error.NoMatchingCall;
    const target_name = storage.name;
    if (tokens[eq_idx + 1].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emitStorageU8StringLiteral(allocator, tokens, eq_idx + 1, target_name, ctx, out);
        return;
    }

    if (try emitStorageAggLiteral(allocator, tokens, eq_idx + 1, end_idx, target_name, storage.elem_ty, locals, ctx, out)) return;

    if (try emitStorageWriteExpr(allocator, tokens, eq_idx + 1, end_idx, target_name, locals, ctx, out)) {
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }

    const expected_ty = findLocalType(locals.locals.items, source_name) orelse return error.NoMatchingCall;
    const emitted_move_call = try emitManagedHandleCallExprWithMoveContext(
        allocator,
        tokens,
        eq_idx + 1,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        expected_ty,
        out,
    );
    if (emitted_move_call or try emitStorageHandleBindingExpr(allocator, tokens, eq_idx + 1, end_idx, body_start, body_end, allow_last_use_move, expected_ty, locals, defer_ctx, ctx, out)) {
        if (!emitted_move_call and isDirectManagedLocalExpr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }

    return error.NoMatchingCall;
}

pub fn emitStorageHandleAssignmentExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, target_source_name: []const u8, target_name: []const u8, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (end_idx == start_idx + 1 and tokens[start_idx].kind == .ident) {
        if (directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx)) |actual_name| {
            if (std.mem.eql(u8, actual_name, target_name)) return true;
        }
    }
    const expected_ty = findLocalType(locals.locals.items, target_name) orelse return false;
    if (!try emitStorageHandleBindingExpr(allocator, tokens, start_idx, end_idx, body_start, body_end, true, expected_ty, locals, defer_ctx, ctx, out)) return false;
    const move_source = directManagedLastUseMoveSource(tokens, start_idx, end_idx, body_end, target_source_name, locals, ctx, defer_ctx);
    if (move_source == null and isDirectManagedLocalExpr(tokens, start_idx, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
    if (move_source) |source| {
        try appendFmt(allocator, out, "    ;; arc-overwrite-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

pub fn emitTupleBinding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 3 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const tuple_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!isTupleTypeName(tuple_local.ty)) return false;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    if (try emitTupleCallBinding(
        allocator,
        tokens,
        start_idx,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        tuple_local,
        out,
    )) {
        return true;
    }
    if (try emitTupleGetBinding(allocator, tokens, start_idx, end_idx, locals, ctx, tuple_local, out)) {
        return true;
    }
    const open_brace = structLiteralOpenRhs(tokens, eq_idx + 1, end_idx) orelse return false;

    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    const arity = tupleArity(tuple_local.ty) orelse return false;
    var expr_start = open_brace + 1;
    var idx: usize = 0;
    while (expr_start < close_brace) {
        const expr_end = findArgEnd(tokens, expr_start, close_brace);
        if (idx >= arity) return error.NoMatchingCall;
        const elem_ty = tupleElementTypeAt(tuple_local.ty, idx) orelse return error.UnsupportedLowering;
        if (!try gen_hooks.emitExpr(allocator, tokens, expr_start, expr_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
        idx += 1;
        expr_start = expr_end;
        if (expr_start < close_brace) {
            if (!tokEq(tokens[expr_start], ",")) return error.NoMatchingCall;
            expr_start += 1;
        }
    }
    if (idx != arity) return error.NoMatchingCall;
    try emitTupleLocalSet(allocator, tuple_local.name, tuple_local.ty, ctx, out);
    return true;
}

pub fn emitStorageAssignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    if (start_idx + 2 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const source_name = tokens[start_idx].lexeme;
    const storage = findStorageLocal(locals.storage_locals.items, source_name) orelse return false;
    const target_name = storage.name;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;
    const rhs_start = start_idx + 2;
    if (rhs_start < end_idx and tokens[rhs_start].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emitOverwriteReleaseManagedLocal(allocator, target_name, out);
        try emitStorageU8StringLiteral(allocator, tokens, rhs_start, target_name, ctx, out);
        return true;
    }
    if (try emitStorageAggLiteral(allocator, tokens, rhs_start, end_idx, STORAGE_OVERWRITE_TMP_LOCAL, storage.elem_ty, locals, ctx, out)) {
        try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
        return true;
    }
    if (try emitStorageHandleAssignmentExpr(allocator, tokens, rhs_start, end_idx, body_start, body_end, source_name, target_name, locals, defer_ctx, ctx, out)) {
        return true;
    }
    if (!try emitStorageWriteExpr(allocator, tokens, rhs_start, end_idx, target_name, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
    return true;
}

pub const ParsedStorageType = struct {
    elem_ty: []const u8,
    next_idx: usize,
};

pub const ManagedPayloadBinding = struct {
    ty: []const u8,
    elem_ty: []const u8,
};

pub const TupleElementInfo = gen_tuple.TupleElementInfo;

pub const StructLiteralFieldRange = struct {
    value_start: usize,
    value_end: usize,
};

pub fn stmtContainsStorageAggLiteral(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokEq(tokens[i], ".") and tokEq(tokens[i + 1], "{")) return true;
    }
    return false;
}

pub fn emitStorageAggReturnValue(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_ty = managedPayloadElemTypeFromName(expected_ty) orelse return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (!isStorageAggLiteralExpr(tokens, range.start, range.end)) return false;
    if (!try emitStorageAggLiteral(allocator, tokens, range.start, range.end, STORAGE_OVERWRITE_TMP_LOCAL, elem_ty, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emitTupleReturnExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, out: *std.ArrayList(u8)) !bool {
    const item = singleTupleResultItem(result_items) orelse return false;
    if (item.abi_len != result_tys.len) return false;
    return try emitTupleExpr(allocator, tokens, start_idx, end_idx, locals, ctx, item.ty, out);
}

pub fn emitStorageU8StringLiteral(allocator: std.mem.Allocator, tokens: []const lexer.Token, string_idx: usize, local_name: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    try emitStorageU8StringLiteralIntoLocal(allocator, tokens, string_idx, local_name, ctx, out);
}

pub fn emitStorageU8StringLiteralValue(allocator: std.mem.Allocator, tokens: []const lexer.Token, string_idx: usize, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    try emitStorageU8StringLiteralIntoLocal(allocator, tokens, string_idx, STORAGE_OVERWRITE_TMP_LOCAL, ctx, out);
    try out.appendSlice(allocator, "    local.get $" ++ STORAGE_OVERWRITE_TMP_LOCAL ++ "\n");
}

pub fn emitStorageU8RawStringValue(allocator: std.mem.Allocator, key: []const u8, local_name: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const data = ctx.string_data.find(key) orelse return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + data.bytes.len});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    try emitStorageLenPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageCapPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageDataPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    memory.copy\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
}

pub fn emitStorageU8StringLiteralIntoLocal(allocator: std.mem.Allocator, tokens: []const lexer.Token, string_idx: usize, local_name: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const data = ctx.string_data.find(tokens[string_idx].lexeme) orelse return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + data.bytes.len});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    try emitStorageLenPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageCapPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageDataPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    memory.copy\n");
}

pub fn emitStorageAggLiteral(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, local_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], ".")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    const type_id = storageTypeIdForElement(elem_ty, ctx);
    const count = countAggLiteralItems(tokens, start_idx + 2, close_brace);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + count * elem_bytes});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{type_id});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    const aggregate_name = if (isManagedLocalType(elem_ty, ctx) and std.mem.eql(u8, local_name, STORAGE_OVERWRITE_TMP_LOCAL))
        STORAGE_WRITE_NEXT_TMP_LOCAL
    else
        local_name;
    if (!std.mem.eql(u8, aggregate_name, local_name)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{aggregate_name});
    }
    try emitStorageLenPtr(allocator, out, aggregate_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{count});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageCapPtr(allocator, out, aggregate_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{count});
    try out.appendSlice(allocator, "    i32.store\n");

    var item_start = start_idx + 2;
    var item_index: usize = 0;
    while (item_start < close_brace) {
        if (tokEq(tokens[item_start], ",")) {
            item_start += 1;
            continue;
        }
        const item_end = findArgEnd(tokens, item_start, close_brace);
        if (item_end == item_start) return error.NoMatchingCall;
        if (isTupleTypeName(elem_ty)) {
            // Multi-value leaves cannot sit under a store address; pack via base temp.
            if (!try gen_hooks.emitExpr(allocator, tokens, item_start, item_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
            try emitStorageDataPtr(allocator, out, aggregate_name);
            if (item_index * elem_bytes != 0) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{item_index * elem_bytes});
                try out.appendSlice(allocator, "    i32.add\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        } else {
            try emitStorageDataPtr(allocator, out, aggregate_name);
            if (item_index * elem_bytes != 0) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{item_index * elem_bytes});
                try out.appendSlice(allocator, "    i32.add\n");
            }
            if (!try gen_hooks.emitExpr(allocator, tokens, item_start, item_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
            if (isManagedLocalType(elem_ty, ctx) and isDirectManagedLocalExpr(tokens, item_start, item_end, locals, ctx)) {
                try out.appendSlice(allocator, "    ;; storage-managed-element-inc\n");
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendStoreForPayloadType(allocator, out, elem_ty);
        }
        item_index += 1;
        item_start = item_end;
        if (item_start < close_brace and tokEq(tokens[item_start], ",")) item_start += 1;
    }
    if (item_index != count) return error.NoMatchingCall;
    if (!std.mem.eql(u8, aggregate_name, local_name)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{aggregate_name});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    }
    return true;
}

pub fn isStorageAggLiteralExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], ".")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    return close_brace + 1 == end_idx;
}

pub fn countAggLiteralItems(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var item_start = start_idx;
    while (item_start < end_idx) {
        if (tokEq(tokens[item_start], ",")) {
            item_start += 1;
            continue;
        }
        const item_end = findArgEnd(tokens, item_start, end_idx);
        if (item_end == item_start) break;
        count += 1;
        item_start = item_end;
        if (item_start < end_idx and tokEq(tokens[item_start], ",")) item_start += 1;
    }
    return count;
}

pub fn emitStoragePayloadPtr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    try storage_wat.emit_storage_payload_ptr(allocator, out, name);
}

pub fn emitStorageLenPtrWithIndent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, indent: []const u8) !void {
    try storage_wat.emit_storage_len_ptr_with_indent(allocator, out, name, indent);
}

pub fn emitStorageCapPtr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    try storage_wat.emit_storage_cap_ptr(allocator, out, name);
}

pub fn emitStorageCapPtrWithIndent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, indent: []const u8) !void {
    try storage_wat.emit_storage_cap_ptr_with_indent(allocator, out, name, indent);
}

pub fn emitStoragePayloadPtrWithIndent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, indent: []const u8) !void {
    try storage_wat.emit_storage_payload_ptr_with_indent(allocator, out, name, indent);
}

pub fn emitStorageContentComparisonCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) return false;
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const cmp_ty = inferStorageContentComparisonType(tokens, args_start, first_end, second_start, second_end, locals, ctx) orelse return false;
    if (try emitManagedPayloadStorageContentComparisonCall(allocator, tokens, args_start, first_end, second_start, second_end, cmp_ty, call_name, locals, ctx, out)) {
        return true;
    }
    if (!try gen_hooks.emitExpr(allocator, tokens, args_start, first_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    if (!try gen_hooks.emitExpr(allocator, tokens, second_start, second_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try out.appendSlice(allocator, "    call $__storage_equal_u8\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

pub fn emitManagedPayloadStorageContentComparisonCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, left_start: usize, left_end: usize, right_start: usize, right_end: usize, cmp_ty: []const u8, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_ty = storageElemTypeFromName(cmp_ty) orelse return false;
    const nested_elem_ty = managedPayloadElemTypeFromName(elem_ty) orelse return false;
    if (!std.mem.eql(u8, nested_elem_ty, "u8")) return false;

    if (!try gen_hooks.emitExpr(allocator, tokens, left_start, left_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    if (!try gen_hooks.emitExpr(allocator, tokens, right_start, right_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});

    try appendFmt(allocator, out, "    i32.const 0\n    local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try appendFmt(allocator, out, "    i32.const 1\n    local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "    block $storage_managed_eq_done\n");
    try emitStorageLenPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try out.appendSlice(allocator, "      i32.load\n");
    try emitStorageLenPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try out.appendSlice(allocator,
        \\      i32.load
        \\      i32.ne
        \\      if
        \\
    );
    try appendFmt(allocator, out, "        i32.const 0\n        local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\        br $storage_managed_eq_done
        \\      end
        \\      loop $storage_managed_eq_loop
        \\
    );
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try emitStorageLenPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try out.appendSlice(allocator,
        \\        i32.load
        \\        i32.ge_u
        \\        br_if $storage_managed_eq_done
        \\
    );
    try emitStorageDataPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\        i32.const 4
        \\        i32.mul
        \\        i32.add
        \\        i32.load
        \\
    );
    try emitStorageDataPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\        i32.const 4
        \\        i32.mul
        \\        i32.add
        \\        i32.load
        \\        call $__storage_equal_u8
        \\        i32.eqz
        \\        if
        \\
    );
    try appendFmt(allocator, out, "          i32.const 0\n          local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\          br $storage_managed_eq_done
        \\        end
        \\
    );
    try appendFmt(allocator, out, "        local.get ${s}\n        i32.const 1\n        i32.add\n        local.set ${s}\n", .{
        STORAGE_WRITE_SCAN_TMP_LOCAL,
        STORAGE_WRITE_SCAN_TMP_LOCAL,
    });
    try out.appendSlice(allocator,
        \\        br $storage_managed_eq_loop
        \\      end
        \\    end
        \\
    );
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

pub fn inferStorageContentComparisonType(
    tokens: []const lexer.Token,
    left_start: usize,
    left_end: usize,
    right_start: usize,
    right_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const left_ty = inferExprType(tokens, left_start, left_end, locals, ctx);
    const right_ty = inferExprType(tokens, right_start, right_end, locals, ctx);
    if (left_ty) |ty| {
        if (isManagedPayloadComparableType(ty) and storageContentArgCompatible(tokens, right_start, right_end, right_ty, ty)) return ty;
    }
    if (right_ty) |ty| {
        if (isManagedPayloadComparableType(ty) and storageContentArgCompatible(tokens, left_start, left_end, left_ty, ty)) return ty;
    }
    if (isStringLiteralArg(tokens, left_start, left_end) and isStringLiteralArg(tokens, right_start, right_end)) return "text";
    return null;
}

pub fn storageContentArgCompatible(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, inferred_ty: ?[]const u8, target_ty: []const u8) bool {
    if (inferred_ty) |ty| return codegenTypesCompatible(target_ty, ty);
    if (isStorageAggLiteralExpr(tokens, start_idx, end_idx)) return true;
    return isStringLiteralArg(tokens, start_idx, end_idx);
}

pub fn isManagedPayloadComparableType(ty: []const u8) bool {
    return managedPayloadElemTypeFromName(ty) != null;
}

pub fn emitStoragePtrLenHostArg(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, host_import: HostImport, param_idx: usize, out: *std.ArrayList(u8)) !bool {
    if (!hostParamIsPtrLen(host_import, param_idx)) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return false;
    if (tokens[range.start].kind != .ident) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emitStorageDataPtr(allocator, out, tokens[range.start].lexeme);
    try emitStorageLenPtr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

pub fn emitTupleExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!isTupleTypeName(expected_ty)) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const tuple_local = findStructLocal(locals.struct_locals.items, tokens[range.start].lexeme) orelse return false;
        if (!std.mem.eql(u8, tuple_local.ty, expected_ty)) return false;
        try emitTupleLocalGet(allocator, tuple_local.name, expected_ty, ctx, out);
        return true;
    }

    const open_brace = structLiteralOpenRhs(tokens, range.start, range.end) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", range.end) catch return false;
    if (close_brace + 1 != range.end) return false;

    const literal_ty = compactTokenText(allocator, tokens, range.start, open_brace) catch return false;
    defer allocator.free(literal_ty);
    if (!std.mem.eql(u8, literal_ty, expected_ty)) return false;

    const arity = tupleArity(expected_ty) orelse return false;
    var expr_start = open_brace + 1;
    var idx: usize = 0;
    while (expr_start < close_brace) {
        const expr_end = findArgEnd(tokens, expr_start, close_brace);
        if (idx >= arity) return error.NoMatchingCall;
        const elem_ty = tupleElementTypeAt(expected_ty, idx) orelse return error.UnsupportedLowering;
        if (!try gen_hooks.emitExpr(allocator, tokens, expr_start, expr_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
        idx += 1;
        expr_start = expr_end;
        if (expr_start < close_brace) {
            if (!tokEq(tokens[expr_start], ",")) return error.NoMatchingCall;
            expr_start += 1;
        }
    }
    if (idx != arity) return error.NoMatchingCall;
    return true;
}

pub fn storageBindingElemType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 5 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const parsed = parseStorageType(tokens, start_idx + 1, end_idx) orelse return null;
    if (findTopLevelToken(tokens, parsed.next_idx, end_idx, "=") == null) return null;
    return parsed.elem_ty;
}

pub fn managedPayloadBinding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ManagedPayloadBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    const ty = tokens[start_idx + 1].lexeme;
    if (storageElemTypeFromName(ty) != null) return null;
    const elem_ty = managedPayloadElemTypeFromName(ty) orelse return null;
    if (findTopLevelToken(tokens, start_idx + 2, end_idx, "=") == null) return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

pub fn parseStorageType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ParsedStorageType {
    if (start_idx + 2 >= end_idx) return null;
    if (!tokEq(tokens[start_idx], "[")) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 2], "]")) return null;
    return .{
        .elem_ty = tokens[start_idx + 1].lexeme,
        .next_idx = start_idx + 3,
    };
}

pub fn emitStorageBoundsCheck(allocator: std.mem.Allocator, tokens: []const lexer.Token, offset_start: usize, offset_end: usize, locals: *const LocalSet, ctx: CodegenContext, storage_name: []const u8, width: usize, out: *std.ArrayList(u8)) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{storage_name});
    if (!try gen_hooks.emitExpr(allocator, tokens, offset_start, offset_end, locals, ctx, "usize", out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{width});
    try out.appendSlice(allocator, "    call $__storage_check_range\n");
}

pub fn emitStorageWriteExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "set")) {
        return try emitStorageSetCall(allocator, tokens, call_head.args_start, call_head.args_end, target_name, locals, ctx, out);
    }
    if (std.mem.eql(u8, call_name, "put")) {
        return try emitStoragePutCall(allocator, tokens, call_head.args_start, call_head.args_end, target_name, locals, ctx, out);
    }
    return false;
}

pub fn emitStorageSetExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return false;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return try emitStorageSetCall(allocator, tokens, start_idx, end_idx, tokens[start_idx].lexeme, locals, ctx, out);
}

pub fn emitStoragePutCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const first_value_start = first_end + 1;
    const first_value_end = findArgEnd(tokens, first_value_start, end_idx);
    if (first_value_end == first_value_start) return false;
    if (first_value_start < end_idx and tokEq(tokens[first_value_start], "...")) {
        if (first_value_end != end_idx) return false;
        return try emitStoragePutSpreadCall(allocator, tokens, first_value_start + 1, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }
    if (first_value_end == end_idx) {
        return try emitStoragePutOneCall(allocator, tokens, first_value_start, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }

    if (!try emitStoragePutOneCall(allocator, tokens, first_value_start, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});

    var value_start = first_value_end;
    while (value_start < end_idx) {
        if (!tokEq(tokens[value_start], ",")) return false;
        value_start += 1;
        if (value_start >= end_idx) return false;
        if (tokEq(tokens[value_start], "...")) return false;

        const value_end = findArgEnd(tokens, value_start, end_idx);
        if (value_end == value_start) return false;
        if (!try emitStoragePutOneCall(allocator, tokens, value_start, value_end, STORAGE_PUT_SOURCE_TMP_LOCAL, STORAGE_PUT_SOURCE_TMP_LOCAL, storage.elem_ty, locals, ctx, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
        try emitReplaceStoragePutSourceTmp(allocator, target_name, out);
        value_start = value_end;
    }

    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    return true;
}

pub fn emitStoragePutExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return false;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return try emitStoragePutCall(allocator, tokens, start_idx, end_idx, tokens[start_idx].lexeme, locals, ctx, out);
}

pub fn emitStoragePutSpreadCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, spread_start: usize, spread_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (spread_end != spread_start + 1 or tokens[spread_start].kind != .ident) return false;
    const rest_name = tokens[spread_start].lexeme;
    const rest = findStoragePrimitiveLocal(locals.storage_locals.items, rest_name) orelse return false;
    if (!std.mem.eql(u8, rest.elem_ty, elem_ty)) return false;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;

    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    if (isDirectManagedLocalExpr(tokens, spread_start, spread_end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 0\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    block $storage_put_spread_done\n");
    try out.appendSlice(allocator, "      loop $storage_put_spread_scan\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emitStorageLenPtr(allocator, out, rest_name);
    try out.appendSlice(allocator, "        i32.load\n");
    try out.appendSlice(allocator, "        i32.ge_u\n");
    try out.appendSlice(allocator, "        br_if $storage_put_spread_done\n");
    if (isManagedLocalType(elem_ty, ctx)) {
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, 4, "        ");
        try out.appendSlice(allocator, "        i32.load\n");
        try out.appendSlice(allocator, "        call $__arc_inc\n");
        try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try out.appendSlice(allocator, "        call $__storage_put_managed_borrow\n");
    } else if (std.mem.eql(u8, elem_ty, "u8")) {
        try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
        try out.appendSlice(allocator, "        call $__storage_put_u8\n");
    } else {
        try emitStoragePutSpreadScalarElement(allocator, rest_name, elem_ty, elem_bytes, ctx, out);
    }
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceStoragePutSourceTmp(allocator, target_name, out);
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

pub fn emitStorageSetScalarCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, index_start: usize, index_end: usize, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-set-scalar\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    if (!try gen_hooks.emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
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
    try emitStorageCloneCurrentLenForElem(allocator, out, source_name, elem_ty, elem_bytes, ctx);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (isTupleTypeName(elem_ty)) {
        if (tupleHasManagedPackLeafCtx(elem_ty, ctx)) {
            // Dec replaced managed leaves before writing new ones.
            try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try emitDecManagedTupleLeavesAtBase(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        }
        if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try appendStoreForPayloadType(allocator, out, elem_ty);
    }
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emitStoragePutSpreadScalarElement(allocator: std.mem.Allocator, rest_name: []const u8, elem_ty: []const u8, elem_bytes: usize, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    try out.appendSlice(allocator, "        ;; storage-put-spread-scalar\n");
    try emitStorageLenPtrWithIndent(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, "        ");
    try out.appendSlice(allocator, "        i32.load\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "        call $__arc_rc\n");
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.eq\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCapPtrWithIndent(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, "        ");
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
    try emitStorageCloneWithLenLocalForElem(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, elem_ty, elem_bytes, STORAGE_WRITE_NEXT_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, ctx);
    try out.appendSlice(allocator, "        end\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (isTupleTypeName(elem_ty)) {
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        // Spread copy: load without owning-inc, store without owning-inc (clone path already inced, or unique).
        try appendLoadTupleScalarLeavesToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
        try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleScalarLeavesFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        if (tupleHasManagedPackLeafCtx(elem_ty, ctx)) {
            // Unique-append path copies handles without clone-inc; share ownership with source element.
            try emitStorageElementPtrFromLocalWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
            try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try emitIncManagedTupleLeavesAtBase(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        }
    } else {
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
        try appendStoreForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
    }
    try emitStorageLenPtrWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, "        ");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.add\n");
    try out.appendSlice(allocator, "        i32.store\n");
}

pub fn emitStoragePutScalarCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-put-scalar\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emitStorageCapPtr(allocator, out, source_name);
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
    try emitStorageCloneWithLenLocalForElem(allocator, out, source_name, elem_ty, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, ctx);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (isTupleTypeName(elem_ty)) {
        if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try appendStoreForPayloadType(allocator, out, elem_ty);
    }
    try emitStorageLenPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.add\n");
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emitStorageCloneCurrentLen(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_bytes: usize) !void {
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneWithLenLocal(allocator, out, source_name, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL);
}

pub fn emitStorageCloneCurrentLenForElem(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_ty: []const u8, elem_bytes: usize, ctx: CodegenContext) !void {
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneWithLenLocalForElem(allocator, out, source_name, elem_ty, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, ctx);
}

pub fn emitStorageCloneManagedCurrentLen(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8) !void {
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneManagedWithLenLocal(allocator, out, source_name, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL);
}

pub fn emitStorageCloneManagedWithLenLocal(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, next_len_local: []const u8, copy_len_local: []const u8) !void {
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
    try emitStorageIncCopiedManagedElements(allocator, out, STORAGE_WRITE_NEXT_TMP_LOCAL, copy_len_local);
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
}

pub fn emitStorageIncCopiedManagedElements(allocator: std.mem.Allocator, out: *std.ArrayList(u8), storage_local: []const u8, copy_len_local: []const u8) !void {
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

pub fn emitStorageCloneWithLenLocal(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_bytes: usize, next_len_local: []const u8, copy_len_local: []const u8) !void {
    try emitStorageCloneWithLenLocalTyped(allocator, out, source_name, elem_bytes, next_len_local, copy_len_local, TYPE_ID_STORAGE_U8, null);
}

pub fn emitStorageCloneWithLenLocalForElem(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_ty: []const u8, elem_bytes: usize, next_len_local: []const u8, copy_len_local: []const u8, ctx: CodegenContext) !void {
    const type_id = storageTypeIdForElement(elem_ty, ctx);
    const pack = storagePackLayoutForElem(elem_ty, ctx);
    try emitStorageCloneWithLenLocalTyped(allocator, out, source_name, elem_bytes, next_len_local, copy_len_local, type_id, pack);
}

pub fn emitStorageCloneWithLenLocalTyped(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, elem_bytes: usize, next_len_local: []const u8, copy_len_local: []const u8, type_id: usize, pack_layout: ?StructLayout) !void {
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

pub fn emitStorageElementPtrFromLocal(allocator: std.mem.Allocator, out: *std.ArrayList(u8), storage_local: []const u8, index_local: []const u8, elem_bytes: usize) !void {
    try storage_wat.emit_storage_element_ptr_from_local(allocator, out, storage_local, index_local, elem_bytes);
}

pub fn emitStorageElementPtrFromLocalWithIndent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), storage_local: []const u8, index_local: []const u8, elem_bytes: usize, indent: []const u8) !void {
    try storage_wat.emit_storage_element_ptr_from_local_with_indent(allocator, out, storage_local, index_local, elem_bytes, indent);
}

pub fn emitStorageAliasProtect(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, target_name: []const u8) !void {
    try storage_wat.emit_storage_alias_protect(allocator, out, source_name, target_name);
}

pub fn emitStorageAliasRelease(allocator: std.mem.Allocator, out: *std.ArrayList(u8), source_name: []const u8, target_name: []const u8) !void {
    try storage_wat.emit_storage_alias_release(allocator, out, source_name, target_name);
}

pub fn emitEmptyStorageU8Value(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try storage_wat.emit_empty_storage_u8_value(allocator, out);
}

pub fn emitEmptyStorageForElemType(allocator: std.mem.Allocator, elem_ty: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    const type_id = storageTypeIdForElement(elem_ty, ctx);
    try storage_wat.emit_empty_storage_with_type_id(allocator, out, type_id, "    ");
}

pub fn storageElementByteWidthForType(elem_ty: []const u8, ctx: CodegenContext) ?usize {
    if (storageElementByteWidth(elem_ty)) |width| return width;
    if (tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx)) |width| return width;
    if (isManagedLocalType(elem_ty, ctx)) return 4;
    return null;
}

pub fn emitNumberConst(allocator: std.mem.Allocator, ctx: CodegenContext, out: *std.ArrayList(u8), lexeme: []const u8, ty: []const u8) !void {
    try appendFmt(allocator, out, "    {s}.const {s}\n", .{ codegenWasmType(ctx, ty), lexeme });
}

pub fn emitTupleFieldPathGetCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, first_end: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const field_ty = tupleFieldPathType(tokens, start_idx, end_idx, first_end, locals, ctx) orelse return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    const index_start = field_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    const elem_info = tupleGetElementInfo(tokens, index_start, index_end, field_ty) orelse return false;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const field_name = publicDeclName(tokens[field_start].lexeme);
    try appendFmt(allocator, out, "    local.get ${s}.{s}.{d}\n", .{ struct_local.name, field_name, elem_info.index });
    if (isManagedLocalType(elem_info.ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}

pub fn isDirectManagedLocalExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    return directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) != null;
}

pub fn storagePackLayoutForElem(elem_ty: []const u8, ctx: CodegenContext) ?StructLayout {
    if (!isTupleTypeName(elem_ty) or !tupleHasManagedPackLeafCtx(elem_ty, ctx)) return null;
    const layout = findStructLayoutExact(ctx.struct_layouts, elem_ty) orelse return null;
    if (!layout.is_storage_pack) return null;
    return layout;
}

pub fn tupleFieldPathType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident or first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme) or field_end >= end_idx or !tokEq(tokens[field_end], ",")) return null;
    const index_start = field_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    if (index_end != end_idx) return null;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null;
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return null;
    const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, publicDeclName(tokens[field_start].lexeme)) orelse
        findStructFieldType(decl, publicDeclName(tokens[field_start].lexeme)) orelse return null;
    if (!isTupleTypeName(field_ty)) return null;
    return field_ty;
}

pub fn findStructLiteralField(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    field_name: []const u8,
) ?StructLiteralFieldRange {
    var field_start = start_idx;
    while (field_start < end_idx) {
        if (tokEq(tokens[field_start], ",")) {
            field_start += 1;
            continue;
        }
        if (tokens[field_start].kind != .ident) return null;
        const assign_idx = findTopLevelToken(tokens, field_start + 1, end_idx, "=") orelse return null;
        const field_end = findStructLiteralFieldEnd(tokens, assign_idx + 1, end_idx);
        if (std.mem.eql(u8, publicDeclName(tokens[field_start].lexeme), field_name)) {
            return .{ .value_start = assign_idx + 1, .value_end = field_end };
        }
        field_start = field_end;
        if (field_start < end_idx and tokEq(tokens[field_start], ",")) field_start += 1;
    }
    return null;
}

pub fn substituteStructFieldType(allocator: std.mem.Allocator, decl: StructDecl, concrete_ty: []const u8, field_ty: []const u8, owned_types: *std.ArrayList([]const u8)) ![]const u8 {
    if (decl.type_params.len == 0) return field_ty;
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    if (!try bindStructTypeArgs(allocator, decl, concrete_ty, &bindings, owned_types)) return field_ty;
    return try substituteGenericTypeOwned(allocator, field_ty, bindings.items, owned_types);
}

pub fn isStructLiteralRhs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return structLiteralOpenRhs(tokens, start_idx, end_idx) != null;
}

pub fn emitReplaceStoragePutSourceTmp(allocator: std.mem.Allocator, target_name: []const u8, out: *std.ArrayList(u8)) !void {
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

pub fn directManagedLocalExprName(
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
        const payload_ty = unionLocalDefaultPayloadType(tokens, union_local) orelse return null;
        if (!isManagedLocalType(payload_ty, ctx)) return null;
        var matched_idx: ?usize = null;
        for (union_local.layout.payload_tys, 0..) |candidate_ty, idx| {
            if (!std.mem.eql(u8, candidate_ty, payload_ty)) continue;
            if (matched_idx != null) return null;
            matched_idx = idx;
        }
        return unionPayloadLocalNameFromLocals(locals.locals.items, union_local.name, matched_idx orelse return null);
    }

    const ty = findLocalType(locals.locals.items, name) orelse return null;
    if (!isManagedLocalType(ty, ctx)) return null;
    if (isUnionPayloadLocalName(locals.union_locals.items, name)) return name;
    return findLocalName(locals.locals.items, name);
}

pub fn emitOverwriteReleaseManagedLocal(allocator: std.mem.Allocator, name: []const u8, out: *std.ArrayList(u8)) !void {
    try appendFmt(allocator, out, "    ;; arc-overwrite-release {s}\n", .{name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
}

pub fn findLocalFieldType(locals: []const Local, base: []const u8, field: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localFieldNameMatches(local.name, base, field)) return local.ty;
        if (local.source_name) |source| {
            if (localFieldNameMatches(source, base, field)) return local.ty;
        }
    }
    return null;
}

pub fn findFuncDeclForCallHead(
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?FuncDecl {
    const name = tokens[call_head.name_idx].lexeme;
    if (!callHeadHasTypeArgs(call_head)) {
        return findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, name);
    }

    var fallback: ?FuncDecl = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, name)) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;

    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!std.mem.eql(u8, func.name, import_ref.alias)) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;

    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, import_ref.alias)) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, publicDeclName(import_ref.target))) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    return fallback;
}

pub fn inferExprType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .ident) {
            if (findNarrowedUnionType(locals.narrowed_union_locals.items, tok.lexeme)) |ty| return substituteGenericType(ty, ctx.type_bindings);
            if (findLocalType(locals.locals.items, tok.lexeme)) |ty| return ty;
            if (findStructLocal(locals.struct_locals.items, tok.lexeme)) |struct_local| return struct_local.ty;
            if (findUnionLocal(locals.union_locals.items, tok.lexeme)) |union_local| {
                return substituteGenericType(union_local.layout.source_ty, ctx.type_bindings);
            }
            if (findCallbackCallArg(ctx.callback_call_args, tok.lexeme)) |callback_arg| return callback_arg.ty;
            return if (localScalarConst(tokens, tok.lexeme)) |local_const| local_const.ty else if (importedScalarConst(ctx, tokens, tok.lexeme)) |imported_const| imported_const.ty else null;
        }
        return null;
    }

    const call_head = exprCallHead(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic) {
        if (shouldInferBoolSpecialCall(call_name, tokens, call_head.args_start, call_head.args_end, locals, ctx)) return "bool";
        if (std.mem.eql(u8, call_name, "is")) return "bool";
        if (std.mem.eql(u8, call_name, "as")) return inferScalarAsCallType(tokens, call_head.args_start, call_head.args_end);
        if (isComparisonCoreFuncName(call_name)) return "bool";
        if (std.mem.eql(u8, call_name, "len")) return "usize";
        if (std.mem.eql(u8, call_name, "set")) return inferSetCallType(tokens, call_head.args_start, call_head.args_end, locals);
        if (std.mem.eql(u8, call_name, "put")) return inferPutCallType(tokens, call_head.args_start, call_head.args_end, locals);
        if (std.mem.eql(u8, call_name, "field_name")) return "text";
        if (std.mem.eql(u8, call_name, "field_index")) return "usize";
        if (std.mem.eql(u8, call_name, "field_has_default")) return "bool";
        if (std.mem.eql(u8, call_name, "field_get")) {
            return inferFieldGetCallType(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (std.mem.eql(u8, call_name, "field_set")) {
            return inferFieldSetCallType(tokens, call_head.args_start, call_head.args_end, locals);
        }
        if (std.mem.eql(u8, call_name, "get")) {
            return inferGetCallType(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (isMemoryLoadName(call_name)) return memoryLoadResultType(call_name);
        if (isNumericCoreFuncName(call_name)) {
            return inferFirstArgTypeOrDefaultS32(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (isBitwiseCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (isCountBitsCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (isNumericUnarySelectCoreFuncName(call_name)) {
            const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            const source_ty = inferExprType(tokens, call_head.args_start, first_end, locals, ctx) orelse "i32";
            return absResultType(source_ty);
        }
        if (isNumericBinarySelectCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (isFloatUnaryCoreFuncName(call_name) or isFloatBinaryCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
    }

    if (findCallbackBinding(ctx.callback_bindings, call_name)) |binding| return binding.shape.return_type;
    if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| return func.result;
    if (findWasiHostImportForTokens(ctx, tokens, call_name)) |import| return wasiDoResultType(import);
    if (findHostImportForTokens(ctx.host_imports, tokens, call_name)) |host_import| return host_import.result;
    return null;
}

pub fn findStructLiteralFieldEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) return i;
    }
    return end_idx;
}

pub fn findStructFieldType(decl: StructDecl, field_name: []const u8) ?[]const u8 {
    for (decl.fields) |field| {
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) return field.ty;
    }
    return null;
}

pub fn localFieldNameMatches(name: []const u8, base: []const u8, field: []const u8) bool {
    if (name.len != base.len + 1 + field.len) return false;
    if (!std.mem.eql(u8, name[0..base.len], base)) return false;
    if (name[base.len] != '.') return false;
    return std.mem.eql(u8, name[base.len + 1 ..], field);
}

pub fn directManagedLastUseMoveSource(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    target_source_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    defer_ctx: ?*const DeferContext,
) ?LastUseManagedMoveSource {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    const source_name = tokens[start_idx].lexeme;
    if (std.mem.eql(u8, source_name, target_source_name)) return null;
    if (hasRegisteredDeferStmt(tokens, defer_ctx)) return null;
    const actual_name = directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) orelse return null;
    const origin = findLocalOrigin(locals.locals.items, source_name) orelse .unknown;
    if (tokenRangeUsesIdent(tokens, end_idx, body_end, source_name)) return null;
    return .{
        .source_name = source_name,
        .actual_name = actual_name,
        .origin = origin,
    };
}

pub fn structLiteralOpenRhs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 >= end_idx) return null;
    if (tokens[start_idx].kind == .ident and tokEq(tokens[start_idx + 1], "{")) return start_idx + 1;
    if (tokens[start_idx].kind == .ident and tokEq(tokens[start_idx + 1], "<")) {
        const close_angle = findMatchingInRange(tokens, start_idx + 1, "<", ">", end_idx) catch return null;
        if (close_angle + 1 < end_idx and tokEq(tokens[close_angle + 1], "{")) return close_angle + 1;
    }
    if (tokEq(tokens[start_idx], ".") and tokEq(tokens[start_idx + 1], "{")) return start_idx + 1;
    return null;
}

pub fn unionPayloadLocalNameFromLocals(
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

pub fn substituteGenericType(ty: []const u8, bindings: []const GenericTypeBinding) []const u8 {
    if (findGenericBinding(bindings, ty)) |binding| return binding.ty;
    return ty;
}

pub fn isUnionPayloadLocalName(union_locals: []const UnionLocal, name: []const u8) bool {
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

pub fn findCallbackCallArg(args: []const CallbackCallArg, name: []const u8) ?CallbackCallArg {
    for (args) |arg| {
        if (std.mem.eql(u8, arg.source_name, name)) return arg;
    }
    return null;
}

pub fn appendTupleLocalFieldsBorrowed(allocator: std.mem.Allocator, out: *LocalSet, tokens: []const lexer.Token, ctx: CodegenContext, base: []const u8, tuple_ty: []const u8) CodegenError!void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        var field_buf: [32]u8 = undefined;
        const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{idx});
        try appendBorrowedLocalField(allocator, out, tokens, ctx, base, field_name, elem_ty);
    }
}

pub fn findFuncDeclForCall(
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
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, name)) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!std.mem.eql(u8, func.name, import_ref.alias)) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, import_ref.alias)) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, publicDeclName(import_ref.target))) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    return fallback;
}

pub fn findLocalName(locals: []const Local, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.name;
    }
    return null;
}

pub fn emitStorageSetCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const index_start = first_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    if (index_end >= end_idx or !tokEq(tokens[index_end], ",")) return false;

    const value_start = index_end + 1;
    const value_end = findArgEnd(tokens, value_start, end_idx);
    if (value_end != end_idx) return false;

    if (isManagedLocalType(storage.elem_ty, ctx)) {
        return try emitStorageSetManagedCall(allocator, tokens, index_start, index_end, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) {
        return try emitStorageSetScalarCall(allocator, tokens, index_start, index_end, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }

    try emitStorageAliasProtect(allocator, out, tokens[start_idx].lexeme, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tokens[start_idx].lexeme});
    if (!try gen_hooks.emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, "u8", out)) return false;
    try out.appendSlice(allocator, "    call $__storage_set_u8\n");
    try emitStorageAliasRelease(allocator, out, tokens[start_idx].lexeme, target_name);
    return true;
}

pub fn emitStoragePutOneCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (isManagedLocalType(elem_ty, ctx)) {
        return try emitStoragePutManagedCall(allocator, tokens, value_start, value_end, source_name, target_name, elem_ty, locals, ctx, out);
    }
    if (!std.mem.eql(u8, elem_ty, "u8")) {
        return try emitStoragePutScalarCall(allocator, tokens, value_start, value_end, source_name, target_name, elem_ty, locals, ctx, out);
    }

    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, "u8", out)) return false;
    try out.appendSlice(allocator, "    call $__storage_put_u8\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    return true;
}

pub fn callExplicitTypeArgsMatchBindings(tokens: []const lexer.Token, call_head: ExprCallHead, bindings: []const GenericTypeBinding) bool {
    if (bindings.len == 0) return false;

    var type_start = call_head.type_args_start;
    var binding_idx: usize = 0;
    while (type_start < call_head.type_args_end) {
        if (binding_idx >= bindings.len) return false;
        if (tokEq(tokens[type_start], ",")) return false;

        const type_end = findTypeArgEnd(tokens, type_start, call_head.type_args_end);
        if (type_end == type_start) return false;
        if (!tokenTextEqualsCompact(tokens, type_start, type_end, bindings[binding_idx].ty)) return false;

        binding_idx += 1;
        type_start = type_end;
        if (type_start < call_head.type_args_end) {
            if (!tokEq(tokens[type_start], ",")) return false;
            type_start += 1;
            if (type_start >= call_head.type_args_end) return false;
        }
    }
    return binding_idx == bindings.len;
}

pub fn callArgsMatchFuncParams(tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, func: FuncDecl) bool {
    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end and (param_idx < func.params.len and !func.params[param_idx].variadic)) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (func.params[param_idx].callback) |callback| {
            if (!callArgMatchesCallbackShape(tokens, arg_start, arg_end, locals, ctx, callback.shape)) return false;
            if (findCallbackBinding(func.callback_bindings, func.params[param_idx].name)) |binding| {
                if (!callArgMatchesConcreteCallbackBinding(tokens, arg_start, arg_end, ctx, callback.shape, binding)) return false;
            }
        } else if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, func.params[param_idx].ty)) {
            return false;
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx == func.params.len) return arg_start >= args_end;
    if (!func.params[param_idx].variadic) return false;
    if (param_idx + 1 != func.params.len) return false;
    return callArgsMatchVariadicTail(tokens, arg_start, args_end, locals, ctx, funcVariadicElemType(func.params[param_idx]));
}

pub fn hasRegisteredDeferStmt(tokens: []const lexer.Token, defer_ctx: ?*const DeferContext) bool {
    var cursor = defer_ctx;
    while (cursor) |scope| {
        const scan_end = @min(scope.registered_end_idx, scope.end_idx);
        var i = scope.start_idx;
        while (i < scan_end) {
            const stmt_end = findStmtEnd(tokens, i, scope.end_idx);
            if (isDeferStmt(tokens, i, stmt_end)) return true;
            i = stmt_end;
        }
        cursor = scope.parent;
    }
    return false;
}

pub fn appendBorrowedLocalField(allocator: std.mem.Allocator, out: *LocalSet, tokens: []const lexer.Token, ctx: CodegenContext, base: []const u8, field: []const u8, ty: []const u8) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    if (isTupleTypeName(ty)) {
        try out.owned_names.append(allocator, name);
        const local_name = try out.appendStructLocal(allocator, name, ty, false);
        try appendTupleLocalFieldsBorrowed(allocator, out, tokens, ctx, local_name, ty);
        return;
    }
    if (findStructDecl(ctx.structs, ty)) |decl| {
        if (findStructLayout(ctx.struct_layouts, ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
            try out.owned_names.append(allocator, name);
            const local_name = try out.appendStructLocal(allocator, name, ty, false);
            for (decl.fields) |sf| {
                const field_ty = try substituteStructFieldType(allocator, decl, ty, sf.ty, &out.owned_names);
                try appendBorrowedLocalField(allocator, out, tokens, ctx, local_name, sf.name, field_ty);
            }
            return;
        }
    }
    try out.owned_names.append(allocator, name);
    if (try parseTypeUnionLayoutFromName(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, &out.owned_names)) |layout| {
        errdefer freeUnionLayout(allocator, layout);
        return out.appendUnionLocal(allocator, name, layout, false, true);
    }
    try out.appendBorrowedLocal(allocator, name, ty, false);
}

pub fn tokenRangeUsesIdent(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, name: []const u8) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i].lexeme, name)) return true;
    }
    return false;
}

pub fn shouldInferBoolSpecialCall(name: []const u8, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    if (!isBoolSpecialFuncName(name)) return false;
    if (std.mem.eql(u8, name, "not")) return true;
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start + 1 and (tokEq(tokens[args_start], "true") or tokEq(tokens[args_start], "false"))) return true;
    const first_ty = inferExprType(tokens, args_start, first_end, locals, ctx) orelse return false;
    return std.mem.eql(u8, first_ty, "bool");
}

pub fn isDeferStmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return start_idx + 1 < end_idx and tokEq(tokens[start_idx], "defer");
}

pub fn callArgMatchesCallbackShape(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    shape: FuncTypeShape,
) bool {
    if (lambdaExprShape(tokens, arg_start, arg_end)) |lambda| {
        return callArgMatchesCallbackLambda(tokens, lambda, locals, ctx, shape);
    }

    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    if (findCallbackBinding(ctx.callback_bindings, tokens[range.start].lexeme)) |binding| {
        return callbackBindingsHaveSameShape(binding.shape, shape);
    }
    return findCallbackRefFunc(tokens, ctx, tokens[range.start].lexeme, shape) != null;
}

fn callArgMatchesCallbackLambda(
    tokens: []const lexer.Token,
    lambda: LambdaExprShape,
    locals: *const LocalSet,
    ctx: CodegenContext,
    shape: FuncTypeShape,
) bool {
    if (lambdaParamCount(tokens, lambda.open_params + 1, lambda.close_params) != shape.param_types.len) return false;
    if (!lambdaExplicitTypesMatchShape(tokens, lambda, shape)) return false;
    if (shape.return_type == null and lambda.is_block and isReturnArrowAt(tokens, lambda.close_params + 1)) {
        if (lambdaExplicitReturnType(tokens, lambda)) |lambda_ret| {
            if (!std.mem.eql(u8, lambda_ret, "nil")) return false;
        }
    }
    return callbackLambdaReturnMatchesShape(tokens, lambda, shape, locals, ctx);
}

pub fn emitStorageSetManagedCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, index_start: usize, index_end: usize, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    try out.appendSlice(allocator, "    ;; storage-set-managed\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    if (!try gen_hooks.emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
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
    try emitStorageCloneManagedCurrentLen(allocator, out, source_name);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    ;; storage-managed-overwrite-dec\n");
    try out.appendSlice(allocator, "    call $__arc_dec\n");
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    if (!try emitManagedStorageValue(allocator, tokens, value_start, value_end, elem_ty, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emitStoragePutManagedCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, value_start: usize, value_end: usize, source_name: []const u8, target_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    try out.appendSlice(allocator, "    ;; storage-put-managed\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emitStorageCapPtr(allocator, out, source_name);
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
    try emitStorageCloneManagedWithLenLocal(allocator, out, source_name, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    if (!try emitManagedStorageValue(allocator, tokens, value_start, value_end, elem_ty, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageLenPtr(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.add\n");
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
    return true;
}

pub fn emitManagedStorageValue(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!try gen_hooks.emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, elem_ty, out)) return false;
    if (isDirectManagedLocalExpr(tokens, start_idx, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    ;; storage-managed-write-inc\n");
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}

pub fn inferScalarAsCallType(tokens: []const lexer.Token, args_start: usize, args_end: usize) ?[]const u8 {
    const target_end = findArgEnd(tokens, args_start, args_end);
    if (target_end == args_start or target_end >= args_end or !tokEq(tokens[target_end], ",")) return null;
    return scalarAsTargetType(tokens, args_start, target_end);
}

pub fn findCallbackBinding(bindings: []const CallbackBinding, name: []const u8) ?CallbackBinding {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.param_name, name)) return binding;
    }
    return null;
}

pub fn scalarAsTargetType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!isScalarAsTargetTypeName(tokens[start_idx].lexeme)) return null;
    return tokens[start_idx].lexeme;
}

pub fn callArgMatchesConcreteCallbackBinding(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, ctx: CodegenContext, shape: FuncTypeShape, binding: CallbackBinding) bool {
    if (!callbackBindingsHaveSameShape(binding.shape, shape)) return false;
    if (lambdaExprShape(tokens, arg_start, arg_end) != null) {
        return binding.kind == .lambda and moduleTokensEqual(binding.arg_tokens, tokens) and binding.arg_start == arg_start and binding.arg_end == arg_end;
    }

    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    const name = tokens[range.start].lexeme;
    if (findCallbackBinding(ctx.callback_bindings, name)) |upstream| {
        return callbackBindingHasSameConcreteArg(binding, upstream);
    }
    if (binding.kind != .func_ref) return false;
    const func_name = binding.func_name orelse return false;
    return moduleTokensEqual(binding.arg_tokens, tokens) and sameCallableSourceName(func_name, name);
}

pub fn isScalarAsTargetTypeName(name: []const u8) bool {
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

pub fn inferSetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (second_end >= end_idx or !tokEq(tokens[second_end], ",")) return null;
    if (findArgEnd(tokens, second_end + 1, end_idx) != end_idx) return null;

    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme)) |storage| return storage.ty;
    if (findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme)) |struct_local| return struct_local.ty;
    return null;
}

pub fn callbackBindingsHaveSameShape(left: FuncTypeShape, right: FuncTypeShape) bool {
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

pub fn callArgMatchesParam(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, locals: *const LocalSet, ctx: CodegenContext, param_ty: []const u8) bool {
    if (findTopLevelTypeSeparator(param_ty, '|') != null) {
        return callArgMatchesUnionParam(tokens, arg_start, arg_end, locals, ctx, param_ty);
    }

    if (inferExprType(tokens, arg_start, arg_end, locals, ctx)) |arg_ty| {
        return codegenTypesCompatible(param_ty, arg_ty);
    }

    if (managedPayloadElemTypeFromName(param_ty) != null and isStorageAggLiteralExpr(tokens, arg_start, arg_end)) {
        return true;
    }

    if (structLiteralExprMatchesType(tokens, arg_start, arg_end, param_ty, ctx)) {
        return true;
    }

    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1) return false;

    const tok = tokens[range.start];
    if (tok.kind == .ident) {
        if (errorEnumBranchValue(tokens, param_ty, tok.lexeme) != null) return true;
        if (valueEnumBranchValue(ctx, tokens, param_ty, tok.lexeme) != null) return true;
        if (findStructLocal(locals.struct_locals.items, tok.lexeme)) |struct_local| {
            return std.mem.eql(u8, struct_local.ty, param_ty);
        }
    }
    if (tok.kind == .number) {
        return isCoreIntegerScalar(param_ty) or isCoreFloatScalar(param_ty);
    }
    if (tok.kind == .string) {
        return std.mem.eql(u8, param_ty, "text") or storageElemTypeFromName(param_ty) != null;
    }
    if (tok.kind == .ident and (std.mem.eql(u8, tok.lexeme, "true") or std.mem.eql(u8, tok.lexeme, "false"))) {
        return std.mem.eql(u8, param_ty, "bool");
    }
    return false;
}

pub fn inferPutCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme)) |storage| return storage.ty;
    return null;
}

pub fn callArgsMatchVariadicTail(tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, elem_ty: []const u8) bool {
    if (args_start >= args_end) return true;
    if (tokEq(tokens[args_start], "...")) {
        const rest_start = args_start + 1;
        if (findArgEnd(tokens, rest_start, args_end) != args_end) return false;
        if (rest_start + 1 != args_end or tokens[rest_start].kind != .ident) return false;
        const rest = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[rest_start].lexeme) orelse return false;
        return std.mem.eql(u8, rest.elem_ty, elem_ty);
    }

    var arg_start = args_start;
    while (arg_start < args_end) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (arg_end == arg_start) return false;
        if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, elem_ty)) return false;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    return true;
}

pub fn callArgMatchesUnionParam(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, locals: *const LocalSet, ctx: CodegenContext, param_ty: []const u8) bool {
    const range = trimParens(tokens, arg_start, arg_end);
    if (range.start >= range.end) return false;
    if (range.end == range.start + 1 and tokEq(tokens[range.start], "nil")) {
        return unionTypeNameHasBranch(param_ty, "nil");
    }
    if (inferExprType(tokens, arg_start, arg_end, locals, ctx)) |arg_ty| {
        if (codegenTypesCompatible(param_ty, arg_ty)) return true;
        return unionTypeNameHasBranch(param_ty, arg_ty);
    }
    return false;
}

pub fn unionTypeNameHasBranch(ty: []const u8, branch_ty: []const u8) bool {
    var branch_start: usize = 0;
    while (branch_start < ty.len) {
        const branch_end = findTopLevelTypeSeparatorFrom(ty, branch_start, '|') orelse ty.len;
        if (std.mem.eql(u8, ty[branch_start..branch_end], branch_ty)) return true;
        branch_start = branch_end + 1;
    }
    return false;
}

pub fn inferFieldGetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != end_idx) return null;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return null;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return null;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return null;
    const field = fieldFromMeta(ctx, meta) orelse return null;
    return field.ty;
}

pub fn funcVariadicElemType(param: FuncParam) []const u8 {
    if (!param.variadic) return param.ty;
    return param.ty;
}

pub fn inferFieldSetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return null;
    if (field_end >= end_idx or !tokEq(tokens[field_end], ",")) return null;
    if (findArgEnd(tokens, field_end + 1, end_idx) != end_idx) return null;
    return (findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null).ty;
}

pub fn findFieldMetaLocal(locals: []const FieldMetaLocal, name: []const u8) ?FieldMetaLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

pub fn structLiteralExprMatchesType(tokens: []const lexer.Token, arg_start: usize, arg_end: usize, param_ty: []const u8, ctx: CodegenContext) bool {
    const range = trimParens(tokens, arg_start, arg_end);
    const open_brace = structLiteralOpenRhs(tokens, range.start, range.end) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", range.end) catch return false;
    if (close_brace + 1 != range.end) return false;
    if (tokens[range.start].kind != .ident) return false;
    const literal_base = tokens[range.start].lexeme;
    if (!std.mem.eql(u8, typeBaseName(param_ty), literal_base)) return false;
    return findStructDecl(ctx.structs, param_ty) != null;
}

pub fn inferGetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;

    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (inferTupleFieldPathGetType(tokens, start_idx, end_idx, first_end, locals, ctx)) |tuple_ty| return tuple_ty;
    if (second_end != end_idx) {
        return inferPathGetCallType(tokens, start_idx, end_idx, first_end, locals, ctx);
    }

    if (second_end == second_start + 1 and isDotIdent(tokens[second_start].lexeme)) {
        if (inferManagedStructExprFieldType(tokens, start_idx, first_end, tokens[second_start].lexeme, locals, ctx)) |field_ty| {
            return field_ty;
        }
    }

    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) {
        const storage_ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return null;
        if (storageElemTypeFromName(storage_ty)) |elem_ty| return elem_ty;
        return null;
    }

    const name = tokens[start_idx].lexeme;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, name)) |storage| return storage.elem_ty;

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (isTupleTypeName(struct_local.ty)) {
            const elem_info = tupleGetElementInfo(tokens, second_start, second_end, struct_local.ty) orelse return null;
            return elem_info.ty;
        }
    }

    if (second_end != second_start + 1 or !isDotIdent(tokens[second_start].lexeme)) return null;

    const field_name = publicDeclName(tokens[second_start].lexeme);
    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (findLocalFieldType(locals.locals.items, struct_local.name, field_name)) |field_ty| return field_ty;
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return null;
        return findStructFieldType(decl, field_name);
    }
    if (findUnionLocal(locals.union_locals.items, name)) |union_local| {
        const payload = unionLocalDefaultStructPayload(tokens, ctx, union_local) orelse return null;
        return findStructFieldType(payload.decl, field_name);
    }
    return null;
}

pub fn lambdaExprShape(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?LambdaExprShape {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end or !tokEq(tokens[range.start], "(")) return null;
    const close_params = findMatchingInRange(tokens, range.start, "(", ")", range.end) catch return null;
    const body_start = lambdaBodyStart(tokens, close_params + 1, range.end) orelse return null;
    if (body_start >= range.end) return null;
    if (tokEq(tokens[body_start], "{")) {
        const close_block = findMatchingInRange(tokens, body_start, "{", "}", range.end) catch return null;
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

pub fn lambdaParamCount(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;
    var count: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) count += 1;
        seg_start = i + 1;
    }
    return count;
}

pub fn callbackBindingHasSameConcreteArg(left: CallbackBinding, right: CallbackBinding) bool {
    if (left.kind != right.kind) return false;
    if (!callbackBindingsHaveSameShape(left.shape, right.shape)) return false;
    return switch (left.kind) {
        .lambda => moduleTokensEqual(left.arg_tokens, right.arg_tokens) and left.arg_start == right.arg_start and left.arg_end == right.arg_end,
        .func_ref => blk: {
            const left_name = left.func_name orelse break :blk false;
            const right_name = right.func_name orelse break :blk false;
            break :blk moduleTokensEqual(left.arg_tokens, right.arg_tokens) and sameCallableSourceName(left_name, right_name);
        },
    };
}

pub fn valueEnumBranchValue(
    ctx: CodegenContext,
    tokens: []const lexer.Token,
    enum_name: []const u8,
    branch_name: []const u8,
) ?[]const u8 {
    if (findValueEnumDecl(ctx.value_enums, enum_name)) |decl| {
        if (findValueEnumBranchValue(decl, branch_name)) |value| return value;
    }
    const import_ref = findCodegenImportByAlias(tokens, branch_name) orelse return null;
    for (ctx.modules) |module| {
        if (!valueEnumSourceMatchesImport(module.tokens, import_ref)) continue;
        const enum_idx = findValueEnumDeclLineByBranch(module.tokens, import_ref.target) orelse return null;
        if (!valueEnumTypeMatchesImportAlias(ctx, module.tokens, enum_idx, enum_name)) return null;
        return valueEnumBranchValueInLine(module.tokens, enum_idx, import_ref.target);
    }
    return null;
}

pub fn inferTupleFieldPathGetType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const field_ty = tupleFieldPathType(tokens, start_idx, end_idx, first_end, locals, ctx) orelse return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    const index_start = field_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    const elem_info = tupleGetElementInfo(tokens, index_start, index_end, field_ty) orelse return null;
    return elem_info.ty;
}

pub fn appendManagedStructFieldMetaLocal(allocator: std.mem.Allocator, out: *LocalSet, base: []const u8, field: []const u8, ty: []const u8) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    try out.owned_names.append(allocator, name);
    try out.locals.append(allocator, .{
        .name = name,
        .ty = ty,
        .emit_decl = false,
        .release_on_scope_exit = false,
    });
}

pub fn fieldFromMeta(ctx: CodegenContext, meta: FieldMetaLocal) ?StructField {
    const decl = findStructDecl(ctx.structs, meta.struct_name) orelse return null;
    if (meta.decl_index >= decl.fields.len) return null;
    return decl.fields[meta.decl_index];
}

pub fn findStructField(decl: StructDecl, field_name: []const u8) ?StructField {
    for (decl.fields) |field| {
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) return field;
    }
    return null;
}

pub fn unionLocalDefaultPayloadType(tokens: []const lexer.Token, union_local: UnionLocal) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (isErrorLikeType(tokens, branch.ty)) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

pub fn unionLocalDefaultStructPayload(tokens: []const lexer.Token, ctx: CodegenContext, union_local: UnionLocal) ?UnionStructPayload {
    var matched: ?UnionStructPayload = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (isErrorLikeType(tokens, branch.ty)) continue;
        const decl = findStructDecl(ctx.structs, branch.ty) orelse continue;
        if (findStructLayout(ctx.struct_layouts, branch.ty) == null and branch.payload_len != decl.fields.len) continue;
        if (findStructLayout(ctx.struct_layouts, branch.ty) != null and branch.payload_len != 1) continue;
        if (matched != null) return null;
        matched = .{ .branch = branch, .decl = decl };
    }
    return matched;
}

pub fn findNarrowedUnionType(locals: []const NarrowedUnionLocal, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.ty;
    }
    return null;
}

pub fn isDotIdent(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}

// Free helpers from codegen_model.
pub const freeCallbackBindings = model.freeCallbackBindings;
pub const freeStructDecls = model.freeStructDecls;
pub const freeStructDecl = model.freeStructDecl;
pub const freeValueEnumDecls = model.freeValueEnumDecls;
pub const freePayloadEnumDecls = model.freePayloadEnumDecls;
pub const freeStructLayouts = model.freeStructLayouts;
pub const freeFuncParams = model.freeFuncParams;
pub const freeFuncDecls = model.freeFuncDecls;
pub const freeFuncResultItems = model.freeFuncResultItems;
const NUMERIC_SELECT_RIGHT_TMP_I64 = constants.NUMERIC_SELECT_RIGHT_TMP_I64;
const NUMERIC_SELECT_LEFT_TMP_I64 = constants.NUMERIC_SELECT_LEFT_TMP_I64;
const NUMERIC_SELECT_RIGHT_TMP_I32 = constants.NUMERIC_SELECT_RIGHT_TMP_I32;
const NUMERIC_SELECT_LEFT_TMP_I32 = constants.NUMERIC_SELECT_LEFT_TMP_I32;
const SourceOrigin = model.SourceOrigin;
const ValueEnumBranch = model.ValueEnumBranch;
const PayloadEnumCase = model.PayloadEnumCase;
const ManagedFieldOffset = model.ManagedFieldOffset;
const TypedStructBinding = model.TypedStructBinding;
const InferredUnionBinding = model.InferredUnionBinding;
const EmitOptions = model.EmitOptions;
const VARIADIC_PACK_TMP_LOCAL = constants.VARIADIC_PACK_TMP_LOCAL;
const TUPLE_PACK_SPILL_I32 = constants.TUPLE_PACK_SPILL_I32;
const TUPLE_PACK_SPILL_I64 = constants.TUPLE_PACK_SPILL_I64;
const TUPLE_PACK_SPILL_F32 = constants.TUPLE_PACK_SPILL_F32;
const TUPLE_PACK_SPILL_F64 = constants.TUPLE_PACK_SPILL_F64;
const NumericSelectTemps = model.NumericSelectTemps;
const EMPTY_LOCAL_SET = context.EMPTY_LOCAL_SET;
const OwnedFuncTypeShape = model.OwnedFuncTypeShape;
const CallbackBindingKind = model.CallbackBindingKind;
const FuncResultParse = model.FuncResultParse;
const MultiResultLhsKind = model.MultiResultLhsKind;
const MultiResultLhs = model.MultiResultLhs;
const NO_RESULT_ITEMS = model.NO_RESULT_ITEMS;
const ParsedCodegenType = model.ParsedCodegenType;
const StructFieldAbiSlot = model.StructFieldAbiSlot;
const FuncBodyShape = model.FuncBodyShape;
const StructErrorResult = model.StructErrorResult;
const SelfTailTco = context.SelfTailTco;
const CollectionLoopHeader = context.CollectionLoopHeader;
const RecvLoopHeader = context.RecvLoopHeader;
const NilComparisonNarrowing = model.NilComparisonNarrowing;
const IsComparisonNarrowing = model.IsComparisonNarrowing;
const DeferItemKind = context.DeferItemKind;
const DeferItem = context.DeferItem;
const CodegenImportPrefix = model.CodegenImportPrefix;
const CodegenImportRef = model.CodegenImportRef;
const ImportedScalarConst = model.ImportedScalarConst;
const ReachVisit = model.ReachVisit;
const StringData = model.StringData;
const findStorageLocalOrigin = context.findStorageLocalOrigin;
const findUnionLocalExact = context.findUnionLocalExact;
const loopSourceLocalName = context.loopSourceLocalName;
const appendLoopSourceStorageLocal = context.appendLoopSourceStorageLocal;

const WasiLinkAtArgs = codegen_wasi_registry.WasiLinkAtArgs;
const WasiLowering = codegen_wasi_registry.WasiLowering;
const WASI_BINDING_ENTRY_SOURCE = codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE;
const knownWasiWitSignature = codegen_wasi_registry.known_wasi_wit_signature;
const wasiLowering = codegen_wasi_registry.wasi_lowering;
const appendWasiImportSymbol = codegen_wasi_registry.append_wasi_import_symbol;
const freeWasiHostImports = codegen_wasi_registry.free_wasi_host_imports;
const findWasiHostImport = codegen_wasi_registry.find_wasi_host_import;
const findWasiHostImportBySource = codegen_wasi_registry.find_wasi_host_import_by_source;
const isWasiHostImportStart = codegen_wasi_registry.is_wasi_host_import_start;
const collectWasiHostImports = codegen_wasi_registry.collect_wasi_host_imports;
const collectWasiHostImportsFromModules = codegen_wasi_registry.collect_wasi_host_imports_from_modules;
const parseWasiHostImport = codegen_wasi_registry.parse_wasi_host_import;
const parseWasiLinkAtArgs = codegen_wasi_registry.parse_wasi_link_at_args;
const wasiCoarseFailedVariantName = codegen_wasi_registry.wasi_coarse_failed_variant_name;
const wasiCoarseClosedVariantName = codegen_wasi_registry.wasi_coarse_closed_variant_name;
const wasiCoarseErrorAlwaysFailed = codegen_wasi_registry.wasi_coarse_error_always_failed;
const isWasiUnionResultBindingCall = codegen_wasi_registry.is_wasi_union_result_binding_call;
const isWasiUnionResultReturnCall = codegen_wasi_registry.is_wasi_union_result_return_call;
const isBareWasiHostCallStatement = codegen_wasi_registry.is_bare_wasi_host_call_statement;
const isWasiResultUnitStatusMultiAssignmentCall = codegen_wasi_registry.is_wasi_result_unit_status_multi_assignment_call;
const isWasiResultReadMultiAssignmentCall = codegen_wasi_registry.is_wasi_result_read_multi_assignment_call;
const isWasiResultListU8StatusMultiAssignmentCall = codegen_wasi_registry.is_wasi_result_list_u8_status_multi_assignment_call;
const wasiHostImportUseIsLowerableAtCall = codegen_wasi_registry.wasi_host_import_use_is_lowerable_at_call;

// Shared types from codegen_model and codegen_context.

pub fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "=") and tokEq(tokens[idx + 1], ">");
}

pub fn lambdaBodyStart(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) ?usize {
    if (isArrowAt(tokens, start_idx)) return start_idx + 2;
    if (start_idx < limit_idx and tokEq(tokens[start_idx], "{")) return start_idx;
    if (start_idx >= limit_idx or !isReturnArrowAt(tokens, start_idx)) return null;

    var i = start_idx + 2;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    while (i < limit_idx) : (i += 1) {
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (depth_angle == 0 and depth_paren == 0 and isArrowAt(tokens, i)) return i + 2;
        if (depth_angle == 0 and depth_paren == 0 and tokEq(tokens[i], "{")) return i;
    }
    return null;
}

pub fn lambdaParamTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 >= end_idx) return null;
    return simpleTypeName(tokens, start_idx + 1, end_idx);
}

pub fn lambdaExplicitReturnType(tokens: []const lexer.Token, lambda: LambdaExprShape) ?[]const u8 {
    if (!isReturnArrowAt(tokens, lambda.close_params + 1)) return null;
    const ret_start = lambda.close_params + 3;
    const ret_end = if (lambda.is_block) lambda.body_start - 1 else lambda.body_start - 2;
    if (ret_start >= ret_end) return null;
    return simpleTypeName(tokens, ret_start, ret_end);
}

pub fn appendTypedLocalWithDecl(allocator: std.mem.Allocator, locals: *LocalSet, name: []const u8, ty: []const u8, ctx: CodegenContext, emit_decl: bool) !void {
    if (managedPayloadElemTypeFromName(ty)) |elem_ty| {
        try locals.appendBorrowedLocal(allocator, name, ty, emit_decl);
        try locals.storage_locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .elem_ty = elem_ty,
        });
        return;
    }

    if (findStructDecl(ctx.structs, ty)) |decl| {
        try locals.struct_locals.append(allocator, .{
            .name = name,
            .ty = ty,
        });
        if (findStructLayout(ctx.struct_layouts, ty) != null) {
            try locals.appendBorrowedLocal(allocator, name, ty, emit_decl);
            for (decl.fields) |field| {
                const field_ty = try substituteStructFieldType(allocator, decl, ty, field.ty, &locals.owned_names);
                try appendManagedStructFieldMetaLocal(allocator, locals, name, field.name, field_ty);
            }
            return;
        }
        for (decl.fields) |field| {
            const field_ty = try substituteStructFieldType(allocator, decl, ty, field.ty, &locals.owned_names);
            try appendBorrowedLocalField(allocator, locals, ctx.entry_tokens, ctx, name, field.name, field_ty);
        }
        return;
    }

    try locals.appendBorrowedLocal(allocator, name, ty, emit_decl);
}

pub fn appendTypedLocal(allocator: std.mem.Allocator, locals: *LocalSet, name: []const u8, ty: []const u8, ctx: CodegenContext) !void {
    return appendTypedLocalWithDecl(allocator, locals, name, ty, ctx, false);
}

pub fn inferLambdaExprReturnType(allocator: std.mem.Allocator, tokens: []const lexer.Token, lambda: LambdaExprShape, shape: FuncTypeShape, locals: *const LocalSet, ctx: CodegenContext) !?[]const u8 {
    if (lambda.close_params + 1 < tokens.len and isReturnArrowAt(tokens, lambda.close_params + 1)) {
        return lambdaExplicitReturnType(tokens, lambda);
    }
    if (lambda.is_block) return "nil";
    if (shape.param_types.len == 0) {
        return inferExprType(tokens, lambda.body_start, lambda.body_end, locals, ctx);
    }

    var lambda_locals = try cloneLocalSet(allocator, locals);
    defer lambda_locals.deinit(allocator);

    var seg_start = lambda.open_params + 1;
    var seg_idx: usize = 0;
    var i = lambda.open_params + 1;
    while (i <= lambda.close_params) : (i += 1) {
        if (i < lambda.close_params and !isTopLevelCommaAny(tokens, i, lambda.open_params + 1, lambda.close_params)) continue;
        if (seg_start < i) {
            if (seg_idx >= shape.param_types.len) return null;
            const param_ty = shape.param_types[seg_idx] orelse return null;
            if (tokens[seg_start].kind != .ident) return null;
            try appendTypedLocal(allocator, &lambda_locals, tokens[seg_start].lexeme, param_ty, ctx);
            seg_idx += 1;
        }
        seg_start = i + 1;
    }
    if (seg_idx != shape.param_types.len) return null;
    return inferExprType(tokens, lambda.body_start, lambda.body_end, &lambda_locals, ctx);
}

pub fn cloneLocalSet(allocator: std.mem.Allocator, locals: *const LocalSet) !LocalSet {
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

pub fn callbackFunctionMatchesShape(func: FuncDecl, shape: FuncTypeShape) bool {
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

pub fn callbackLambdaReturnMatchesShape(tokens: []const lexer.Token, lambda: LambdaExprShape, shape: FuncTypeShape, locals: *const LocalSet, ctx: CodegenContext) bool {
    if (shape.return_type) |ret_ty| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const lambda_ret = inferLambdaExprReturnType(arena.allocator(), tokens, lambda, shape, locals, ctx) catch return false;
        if (lambda_ret) |actual| {
            if (std.mem.eql(u8, actual, "nil")) return std.mem.eql(u8, ret_ty, "nil");
            return std.mem.eql(u8, ret_ty, actual);
        }
        return false;
    }
    if (!lambda.is_block) return true;
    if (isReturnArrowAt(tokens, lambda.close_params + 1)) {
        if (lambdaExplicitReturnType(tokens, lambda)) |lambda_ret| {
            return std.mem.eql(u8, lambda_ret, "nil");
        }
        return false;
    }
    return true;
}

pub fn findCallbackRefFunc(tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8, shape: FuncTypeShape) ?FuncDecl {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, name)) continue;
        if (callbackFunctionMatchesShape(func, shape)) return func;
    }
    return null;
}

pub fn lambdaExplicitTypesMatchShape(tokens: []const lexer.Token, lambda: LambdaExprShape, shape: FuncTypeShape) bool {
    var seg_start = lambda.open_params + 1;
    var seg_idx: usize = 0;
    var i = lambda.open_params + 1;
    while (i <= lambda.close_params) : (i += 1) {
        if (i < lambda.close_params and !isTopLevelCommaAny(tokens, i, lambda.open_params + 1, lambda.close_params)) continue;
        if (seg_start < i) {
            if (seg_idx >= shape.param_types.len) return false;
            if (lambdaParamTypeName(tokens, seg_start, i)) |ty| {
                const expected = shape.param_types[seg_idx] orelse return false;
                if (!std.mem.eql(u8, expected, ty)) return false;
            }
            seg_idx += 1;
        }
        seg_start = i + 1;
    }
    return seg_idx == shape.param_types.len;
}

pub fn typeBaseName(ty: []const u8) []const u8 {
    return type_util.typeBaseName(ty);
}

pub fn valueEnumTypeMatchesImportAlias(ctx: CodegenContext, tokens: []const lexer.Token, enum_idx: usize, expected_name: []const u8) bool {
    const source_name = publicDeclName(tokens[enum_idx].lexeme);
    if (std.mem.eql(u8, source_name, expected_name)) return true;
    const decl = findValueEnumDecl(ctx.value_enums, expected_name) orelse return false;
    return std.mem.eql(u8, decl.source_name, source_name);
}

pub fn findValueEnumBranchValue(decl: ValueEnumDecl, branch_name: []const u8) ?[]const u8 {
    for (decl.branches) |branch| {
        if (std.mem.eql(u8, branch.name, branch_name)) return branch.value;
    }
    return null;
}

pub fn valueEnumBranchValueInLine(tokens: []const lexer.Token, enum_idx: usize, branch_name: []const u8) ?[]const u8 {
    const line_end = findLineEnd(tokens, enum_idx);
    var j = enum_idx + 3;
    while (j + 3 < line_end) {
        if (tokEq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind == .ident and std.mem.eql(u8, publicDeclName(tokens[j].lexeme), branch_name)) return tokens[j + 2].lexeme;
        j += 4;
    }
    return null;
}

pub fn valueEnumSourceMatchesImport(tokens: []const lexer.Token, import_ref: CodegenImportRef) bool {
    if (findValueEnumDeclLineByName(tokens, import_ref.target) != null) return true;
    return findValueEnumDeclLineByBranch(tokens, import_ref.target) != null;
}

pub fn managedPayloadElemTypeFromName(ty: []const u8) ?[]const u8 {
    return type_util.managedPayloadElemTypeFromName(ty);
}

pub fn absResultType(source_ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, source_ty, "i8")) return "u8";
    if (std.mem.eql(u8, source_ty, "i16")) return "u16";
    if (std.mem.eql(u8, source_ty, "i32")) return "u32";
    if (std.mem.eql(u8, source_ty, "i64")) return "u64";
    if (std.mem.eql(u8, source_ty, "isize")) return "usize";
    if (std.mem.eql(u8, source_ty, "f32")) return "f32";
    if (std.mem.eql(u8, source_ty, "f64")) return "f64";
    return null;
}

pub fn inferFirstArgTypeOrDefaultS32(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, args_start, args_end);
    return inferExprType(tokens, args_start, first_end, locals, ctx) orelse "i32";
}

pub fn wasiDoResultType(import: WasiHostImport) ?[]const u8 {
    const lowering = wasiLowering(import) orelse return null;
    if (lowering.result_storage_elem) |elem_ty| return storageTypeNameForElem(elem_ty);
    if (lowering.result_list_preopen) return "[Tuple<Dir,text>]";
    if (lowering.result_record) |record| return record;
    return import.result;
}

pub fn memoryLoadResultType(name: []const u8) ?[]const u8 {
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

pub fn inferPathGetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    var current_ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return null;
    var segment_start = first_end + 1;
    while (segment_start < end_idx) {
        const segment_end = findArgEnd(tokens, segment_start, end_idx);
        if (segment_end == segment_start) return null;
        const has_more = segment_end < end_idx;
        if (has_more and !tokEq(tokens[segment_end], ",")) return null;

        if (segment_end == segment_start + 1 and isDotIdent(tokens[segment_start].lexeme)) {
            const decl = findStructDecl(ctx.structs, current_ty) orelse return null;
            const field_ty = findConcreteStructFieldTypeNoAlloc(decl, current_ty, publicDeclName(tokens[segment_start].lexeme)) orelse return null;
            current_ty = substituteGenericType(field_ty, ctx.type_bindings);
        } else if (isTupleTypeName(current_ty)) {
            const elem_info = tupleGetElementInfo(tokens, segment_start, segment_end, current_ty) orelse return null;
            current_ty = elem_info.ty;
        } else {
            current_ty = storageElemTypeFromName(current_ty) orelse return null;
        }

        if (!has_more) return current_ty;
        segment_start = segment_end + 1;
    }
    return null;
}

pub fn inferManagedStructExprFieldType(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    dot_field: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (value_end == value_start + 1 and tokens[value_start].kind == .ident) return null;
    const struct_ty = inferExprType(tokens, value_start, value_end, locals, ctx) orelse return null;
    if (findStructLayout(ctx.struct_layouts, struct_ty) == null) return null;
    const decl = findStructDecl(ctx.structs, struct_ty) orelse return null;
    return findConcreteStructFieldTypeNoAlloc(decl, struct_ty, publicDeclName(dot_field));
}

pub fn findConcreteStructFieldTypeNoAlloc(decl: StructDecl, concrete_ty: []const u8, field_name: []const u8) ?[]const u8 {
    const field = findStructField(decl, field_name) orelse return null;
    if (decl.type_params.len == 0) return field.ty;
    for (decl.type_params, 0..) |type_param, idx| {
        if (!std.mem.eql(u8, field.ty, type_param)) continue;
        return genericTypeArgAt(concrete_ty, idx);
    }
    return field.ty;
}

pub fn genericTypeArgAt(concrete_ty: []const u8, target_idx: usize) ?[]const u8 {
    return type_util.genericTypeArgAt(concrete_ty, target_idx);
}

pub fn emitManagedHandleCallExprWithMoveContext(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != 1) return false;
    if (!std.mem.eql(u8, func.results[0], expected_ty)) return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    return try gen_hooks.emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out);
}

pub fn emitStorageHandleBindingExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, allow_last_use_move: bool, expected_ty: []const u8, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!std.mem.eql(u8, inferExprType(tokens, start_idx, end_idx, locals, ctx) orelse "", expected_ty)) return false;
    const move_ctx = if (allow_last_use_move) CallLastUseMoveContext{
        .body_start = body_start,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
        .allow_field_read_move = true,
    } else null;
    if (!try gen_hooks.emitExprWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, if (move_ctx) |*ctx_info| ctx_info else null, out)) return false;
    return true;
}

pub fn emitTupleCallBinding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, tuple_local: StructLocal, out: *std.ArrayList(u8)) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const result_struct = func.result_struct orelse return false;
    if (!std.mem.eql(u8, result_struct, tuple_local.ty)) return false;
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypes(allocator, tuple_local.ty, &leaf_types);
    if (func.results.len != leaf_types.items.len) return error.NoMatchingCall;
    for (leaf_types.items, 0..) |leaf_ty, idx| {
        if (!std.mem.eql(u8, leaf_ty, func.results[idx])) return error.NoMatchingCall;
    }
    const move_ctx = CallLastUseMoveContext{
        .body_start = 0,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try gen_hooks.emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    try emitTupleLocalSet(allocator, tuple_local.name, tuple_local.ty, ctx, out);
    return true;
}
