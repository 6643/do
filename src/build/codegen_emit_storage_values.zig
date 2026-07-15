//! Storage literals, bindings, and value construction emission.

const storage_layout = @import("codegen_storage_layout.zig");
const ManagedPayloadBinding = storage_layout.ManagedPayloadBinding;
const ParsedStorageType = storage_layout.ParsedStorageType;
const find_func_decl_for_call_head = storage_layout.find_func_decl_for_call_head;
const infer_expr_type = storage_layout.infer_expr_type;
const infer_storage_content_comparison_type = storage_layout.infer_storage_content_comparison_type;
const is_storage_agg_literal_expr = storage_layout.is_storage_agg_literal_expr;
const managed_payload_elem_type_from_name = storage_layout.managed_payload_elem_type_from_name;
const storage_element_byte_width_for_type = storage_layout.storage_element_byte_width_for_type;
const struct_literal_open_rhs = storage_layout.struct_literal_open_rhs;
const tuple_field_path_type = storage_layout.tuple_field_path_type;

const storage_operations = @import("codegen_emit_storage_operations.zig");
const direct_managed_local_expr_name = storage_operations.direct_managed_local_expr_name;
const emit_overwrite_release_managed_local = storage_operations.emit_overwrite_release_managed_local;
const emit_storage_cap_ptr = storage_operations.emit_storage_cap_ptr;
const emit_storage_write_expr = storage_operations.emit_storage_write_expr;
const is_direct_managed_local_expr = storage_operations.is_direct_managed_local_expr;

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
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const gen_import = @import("gen_import.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_emit_tuple = @import("codegen_emit_tuple.zig");
const findValueEnumDeclLineByName = gen_import.findValueEnumDeclLineByName;
const findValueEnumDeclLineByBranch = gen_import.findValueEnumDeclLineByBranch;
const simple_type_name = codegen_collect_functions.simple_type_name;
const is_top_level_comma_any = codegen_collect_functions.is_top_level_comma_any;
const is_return_arrow_at = codegen_collect_functions.is_return_arrow_at;
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

const findStructDecl = gen_collect_util.findStructDecl;
const findStructLayout = gen_collect_util.findStructLayout;
const find_struct_layout_exact = codegen_collect_structs.find_struct_layout_exact;
const is_pack_managed_handle_leaf = codegen_collect_structs.is_pack_managed_handle_leaf;
const leaf_payload_bytes_for_pack = codegen_collect_structs.leaf_payload_bytes_for_pack;
const pureScalarStructPackWidth = gen_collect_util.pureScalarStructPackWidth;
const packSlotWidth = gen_collect_util.packSlotWidth;
const tuplePackWidthWithStructs = gen_collect_util.tuplePackWidthWithStructs;
const appendTupleLeafTypesWithStructs = gen_collect_util.appendTupleLeafTypesWithStructs;
const appendTupleLeafTypes = gen_collect_util.appendTupleLeafTypes;
const structDeclHasManagedField = gen_collect_util.structDeclHasManagedField;
const ensure_storage_pack_layout = codegen_collect_structs.ensure_storage_pack_layout;
const managed_leaf_field_name = codegen_collect_structs.managed_leaf_field_name;
const isErrorLikeType = gen_collect_util.isErrorLikeType;
const parseCodegenTypeExpr = gen_collect_util.parseCodegenTypeExpr;
const parse_type_union_layout_from_name = codegen_collect_structs.parse_type_union_layout_from_name;
const bind_struct_type_args = codegen_collect_structs.bind_struct_type_args;
const substituteGenericTypeOwned = gen_collect_util.substituteGenericTypeOwned;
const findGenericBinding = gen_collect_util.findGenericBinding;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const funcParamAbiType = gen_collect_util.funcParamAbiType;
const isUnmanagedScalarStruct = gen_collect_util.isUnmanagedScalarStruct;
const appendUnionBranchPayloadTypes = gen_collect_util.appendUnionBranchPayloadTypes;

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

const is_managed_local_type = codegen_emit_wasi.is_managed_local_type;
const is_managed_payload_type = codegen_emit_wasi.is_managed_payload_type;
const is_storage_type_name = codegen_emit_wasi.is_storage_type_name;
const storage_elem_type_from_name = codegen_emit_wasi.storage_elem_type_from_name;
const storage_element_byte_width = codegen_emit_wasi.storage_element_byte_width;
const storage_type_id_for_element = codegen_emit_wasi.storage_type_id_for_element;
const type_payload_bytes = codegen_emit_wasi.type_payload_bytes;
const type_payload_alignment = codegen_emit_wasi.type_payload_alignment;
const is_tuple_type_name = codegen_emit_wasi.is_tuple_type_name;
const tuple_arity = codegen_emit_wasi.tuple_arity;
const tuple_element_type_at = codegen_emit_wasi.tuple_element_type_at;
const codegen_wasm_type = codegen_emit_wasi.codegen_wasm_type;
const codegen_types_compatible = codegen_emit_wasi.codegen_types_compatible;
const find_storage_primitive_local = codegen_emit_wasi.find_storage_primitive_local;
const emit_replace_managed_local_from_tmp = codegen_emit_wasi.emit_replace_managed_local_from_tmp;
const emit_storage_data_ptr = codegen_emit_wasi.emit_storage_data_ptr;
const emit_storage_len_ptr = codegen_emit_wasi.emit_storage_len_ptr;
const append_load_for_payload_type = codegen_emit_wasi.append_load_for_payload_type;
const struct_field_payload_offset = codegen_emit_wasi.struct_field_payload_offset;
const find_union_branch_by_type = codegen_emit_wasi.find_union_branch_by_type;
const error_enum_branch_value = codegen_emit_wasi.error_enum_branch_value;
const tuple_scalar_leaf_storage_byte_width = codegen_emit_wasi.tuple_scalar_leaf_storage_byte_width;
const tuple_scalar_leaf_storage_byte_width_ctx = codegen_emit_wasi.tuple_scalar_leaf_storage_byte_width_ctx;
const tuple_has_managed_pack_leaf = codegen_emit_wasi.tuple_has_managed_pack_leaf;
const tuple_has_managed_pack_leaf_with_structs = codegen_emit_wasi.tuple_has_managed_pack_leaf_with_structs;
const tuple_has_managed_pack_leaf_ctx = codegen_emit_wasi.tuple_has_managed_pack_leaf_ctx;
const emit_wasi_host_import_expr = codegen_emit_wasi.emit_wasi_host_import_expr;
const emit_bare_wasi_host_import_call = codegen_emit_wasi.emit_bare_wasi_host_import_call;
const emit_wasi_unit_result_as_union_value = codegen_emit_wasi.emit_wasi_unit_result_as_union_value;
const emit_wasi_filesize_result_as_union_value = codegen_emit_wasi.emit_wasi_filesize_result_as_union_value;
const emit_wasi_read_result_as_union_value = codegen_emit_wasi.emit_wasi_read_result_as_union_value;
const emit_wasi_list_u8_result_as_union_value = codegen_emit_wasi.emit_wasi_list_u8_result_as_union_value;
const emit_wasi_descriptor_result_as_union_value = codegen_emit_wasi.emit_wasi_descriptor_result_as_union_value;
const emit_wasi_record_struct_binding = codegen_emit_wasi.emit_wasi_record_struct_binding;
const isTuplePackableLeafType = type_util.isTuplePackableLeafType;
const isCoreWasmScalar_tu = type_util.isCoreWasmScalar;

const hostParamIsPtrLen = gen_host.hostParamIsPtrLen;
const hostArgCouldBeStoragePtrLenSyntax = gen_host.hostArgCouldBeStoragePtrLenSyntax;
const findHostImportForTokens = gen_host.findHostImportForTokens;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;

// Re-export tuple pack helpers (physical home: codegen_emit_tuple.zig).
pub const appendIncManagedTupleLeavesOnStackCtx = codegen_emit_tuple.append_inc_managed_tuple_leaves_on_stack_ctx;
pub const appendLoadForPayloadTypeWithIndent = codegen_emit_tuple.append_load_for_payload_type_with_indent;
pub const appendLoadTupleElementFromPackedBaseCtx = codegen_emit_tuple.append_load_tuple_element_from_packed_base_ctx;
pub const appendLoadTupleElementOwningFromPackedBase = codegen_emit_tuple.append_load_tuple_element_owning_from_packed_base;
pub const appendLoadTupleLeafTypesOfStructToStack = codegen_emit_tuple.append_load_tuple_leaf_types_of_struct_to_stack;
pub const appendLoadTupleLeavesOwningToStack = codegen_emit_tuple.append_load_tuple_leaves_owning_to_stack;
pub const appendLoadTupleLeavesOwningToStackCtx = codegen_emit_tuple.append_load_tuple_leaves_owning_to_stack_ctx;
pub const appendLoadTupleScalarLeavesToStack = codegen_emit_tuple.append_load_tuple_scalar_leaves_to_stack;
pub const appendLoadTupleScalarLeavesToStackCtx = codegen_emit_tuple.append_load_tuple_scalar_leaves_to_stack_ctx;
pub const appendStoreForPayloadType = codegen_emit_tuple.append_store_for_payload_type;
pub const appendStoreForPayloadTypeWithIndent = codegen_emit_tuple.append_store_for_payload_type_with_indent;
pub const appendStoreTupleLeavesOwningFromStack = codegen_emit_tuple.append_store_tuple_leaves_owning_from_stack;
pub const appendStoreTupleLeavesOwningFromStackCtx = codegen_emit_tuple.append_store_tuple_leaves_owning_from_stack_ctx;
pub const appendStoreTupleScalarLeavesFromStack = codegen_emit_tuple.append_store_tuple_scalar_leaves_from_stack;
pub const appendStoreTupleScalarLeavesFromStackCtx = codegen_emit_tuple.append_store_tuple_scalar_leaves_from_stack_ctx;
pub const emitDecManagedTupleLeavesAtBase = codegen_emit_tuple.emit_dec_managed_tuple_leaves_at_base;
pub const emitIncManagedTupleLeavesAtBase = codegen_emit_tuple.emit_inc_managed_tuple_leaves_at_base;
pub const emitPureScalarStructLocalGet = codegen_emit_tuple.emit_pure_scalar_struct_local_get;
pub const emitPureScalarStructLocalSet = codegen_emit_tuple.emit_pure_scalar_struct_local_set;
pub const emitStorageIncCopiedPackElements = codegen_emit_tuple.emit_storage_inc_copied_pack_elements;
pub const emitTupleGetBinding = codegen_emit_tuple.emit_tuple_get_binding;
pub const emitTupleLocalGet = codegen_emit_tuple.emit_tuple_local_get;
pub const emitTupleLocalSet = codegen_emit_tuple.emit_tuple_local_set;
pub const emitTupleReturnLocal = codegen_emit_tuple.emit_tuple_return_local;
pub const singleTupleResultItem = codegen_emit_tuple.single_tuple_result_item;
pub const tupleElementPackOffsetWithStructs = codegen_emit_tuple.tuple_element_pack_offset_with_structs;
pub const tupleGetElementInfo = codegen_emit_tuple.tuple_get_element_info;
pub const tuplePackSpillLocal = codegen_emit_tuple.tuple_pack_spill_local;

pub fn emit_storage_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const source_name = tokens[start_idx].lexeme;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    const storage = findStorageLocal(locals.storage_locals.items, source_name) orelse return error.NoMatchingCall;
    const target_name = storage.name;
    if (tokens[eq_idx + 1].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emit_storage_u8_string_literal(allocator, tokens, eq_idx + 1, target_name, ctx, out);
        return;
    }

    if (try emit_storage_agg_literal(allocator, tokens, eq_idx + 1, end_idx, target_name, storage.elem_ty, locals, ctx, out)) return;

    if (try emit_storage_write_expr(allocator, tokens, eq_idx + 1, end_idx, target_name, locals, ctx, out)) {
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }

    const expected_ty = findLocalType(locals.locals.items, source_name) orelse return error.NoMatchingCall;
    const emitted_move_call = try emit_managed_handle_call_expr_with_move_context(
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
    if (emitted_move_call or try emit_storage_handle_binding_expr(allocator, tokens, eq_idx + 1, end_idx, body_start, body_end, allow_last_use_move, expected_ty, locals, defer_ctx, ctx, out)) {
        if (!emitted_move_call and is_direct_managed_local_expr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }

    return error.NoMatchingCall;
}

pub fn emit_storage_handle_assignment_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, target_source_name: []const u8, target_name: []const u8, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (end_idx == start_idx + 1 and tokens[start_idx].kind == .ident) {
        if (direct_managed_local_expr_name(tokens, start_idx, end_idx, locals, ctx)) |actual_name| {
            if (std.mem.eql(u8, actual_name, target_name)) return true;
        }
    }
    const expected_ty = findLocalType(locals.locals.items, target_name) orelse return false;
    if (!try emit_storage_handle_binding_expr(allocator, tokens, start_idx, end_idx, body_start, body_end, true, expected_ty, locals, defer_ctx, ctx, out)) return false;
    const move_source = direct_managed_last_use_move_source(tokens, start_idx, end_idx, body_end, target_source_name, locals, ctx, defer_ctx);
    if (move_source == null and is_direct_managed_local_expr(tokens, start_idx, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emit_replace_managed_local_from_tmp(allocator, target_name, out);
    if (move_source) |source| {
        try appendFmt(allocator, out, "    ;; arc-overwrite-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

pub fn emit_tuple_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 3 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const tuple_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!is_tuple_type_name(tuple_local.ty)) return false;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    if (try emit_tuple_call_binding(
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
    const open_brace = struct_literal_open_rhs(tokens, eq_idx + 1, end_idx) orelse return false;

    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    const arity = tuple_arity(tuple_local.ty) orelse return false;
    var expr_start = open_brace + 1;
    var idx: usize = 0;
    while (expr_start < close_brace) {
        const expr_end = findArgEnd(tokens, expr_start, close_brace);
        if (idx >= arity) return error.NoMatchingCall;
        const elem_ty = tuple_element_type_at(tuple_local.ty, idx) orelse return error.UnsupportedLowering;
        if (!try codegen_callbacks.emit_expr(allocator, tokens, expr_start, expr_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
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

pub fn emit_storage_assignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    if (start_idx + 2 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const source_name = tokens[start_idx].lexeme;
    const storage = findStorageLocal(locals.storage_locals.items, source_name) orelse return false;
    const target_name = storage.name;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;
    const rhs_start = start_idx + 2;
    if (rhs_start < end_idx and tokens[rhs_start].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emit_overwrite_release_managed_local(allocator, target_name, out);
        try emit_storage_u8_string_literal(allocator, tokens, rhs_start, target_name, ctx, out);
        return true;
    }
    if (try emit_storage_agg_literal(allocator, tokens, rhs_start, end_idx, STORAGE_OVERWRITE_TMP_LOCAL, storage.elem_ty, locals, ctx, out)) {
        try emit_replace_managed_local_from_tmp(allocator, target_name, out);
        return true;
    }
    if (try emit_storage_handle_assignment_expr(allocator, tokens, rhs_start, end_idx, body_start, body_end, source_name, target_name, locals, defer_ctx, ctx, out)) {
        return true;
    }
    if (!try emit_storage_write_expr(allocator, tokens, rhs_start, end_idx, target_name, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emit_replace_managed_local_from_tmp(allocator, target_name, out);
    return true;
}

pub const TupleElementInfo = codegen_emit_tuple.TupleElementInfo;

pub const StructLiteralFieldRange = struct {
    value_start: usize,
    value_end: usize,
};

pub fn stmt_contains_storage_agg_literal(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokEq(tokens[i], ".") and tokEq(tokens[i + 1], "{")) return true;
    }
    return false;
}

pub fn emit_storage_agg_return_value(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_ty = managed_payload_elem_type_from_name(expected_ty) orelse return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (!is_storage_agg_literal_expr(tokens, range.start, range.end)) return false;
    if (!try emit_storage_agg_literal(allocator, tokens, range.start, range.end, STORAGE_OVERWRITE_TMP_LOCAL, elem_ty, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn emit_tuple_return_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, out: *std.ArrayList(u8)) !bool {
    const item = singleTupleResultItem(result_items) orelse return false;
    if (item.abi_len != result_tys.len) return false;
    return try emit_tuple_expr(allocator, tokens, start_idx, end_idx, locals, ctx, item.ty, out);
}

pub fn emit_storage_u8_string_literal(allocator: std.mem.Allocator, tokens: []const lexer.Token, string_idx: usize, local_name: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    try emit_storage_u8_string_literal_into_local(allocator, tokens, string_idx, local_name, ctx, out);
}

pub fn emit_storage_u8_string_literal_value(allocator: std.mem.Allocator, tokens: []const lexer.Token, string_idx: usize, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    try emit_storage_u8_string_literal_into_local(allocator, tokens, string_idx, STORAGE_OVERWRITE_TMP_LOCAL, ctx, out);
    try out.appendSlice(allocator, "    local.get $" ++ STORAGE_OVERWRITE_TMP_LOCAL ++ "\n");
}

pub fn emit_storage_u8_raw_string_value(allocator: std.mem.Allocator, key: []const u8, local_name: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const data = ctx.string_data.find(key) orelse return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + data.bytes.len});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    try emit_storage_len_ptr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_cap_ptr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_data_ptr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    memory.copy\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
}

pub fn emit_storage_u8_string_literal_into_local(allocator: std.mem.Allocator, tokens: []const lexer.Token, string_idx: usize, local_name: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const data = ctx.string_data.find(tokens[string_idx].lexeme) orelse return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + data.bytes.len});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    try emit_storage_len_ptr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_cap_ptr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_data_ptr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    memory.copy\n");
}

pub fn emit_storage_agg_literal(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, local_name: []const u8, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], ".")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    const elem_bytes = storage_element_byte_width_for_type(elem_ty, ctx) orelse return false;
    const type_id = storage_type_id_for_element(elem_ty, ctx);
    const count = count_agg_literal_items(tokens, start_idx + 2, close_brace);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + count * elem_bytes});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{type_id});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    const aggregate_name = if (is_managed_local_type(elem_ty, ctx) and std.mem.eql(u8, local_name, STORAGE_OVERWRITE_TMP_LOCAL))
        STORAGE_WRITE_NEXT_TMP_LOCAL
    else
        local_name;
    if (!std.mem.eql(u8, aggregate_name, local_name)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{aggregate_name});
    }
    try emit_storage_len_ptr(allocator, out, aggregate_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{count});
    try out.appendSlice(allocator, "    i32.store\n");
    try emit_storage_cap_ptr(allocator, out, aggregate_name);
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
        if (is_tuple_type_name(elem_ty)) {
            // Multi-value leaves cannot sit under a store address; pack via base temp.
            if (!try codegen_callbacks.emit_expr(allocator, tokens, item_start, item_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
            try emit_storage_data_ptr(allocator, out, aggregate_name);
            if (item_index * elem_bytes != 0) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{item_index * elem_bytes});
                try out.appendSlice(allocator, "    i32.add\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        } else {
            try emit_storage_data_ptr(allocator, out, aggregate_name);
            if (item_index * elem_bytes != 0) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{item_index * elem_bytes});
                try out.appendSlice(allocator, "    i32.add\n");
            }
            if (!try codegen_callbacks.emit_expr(allocator, tokens, item_start, item_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
            if (is_managed_local_type(elem_ty, ctx) and is_direct_managed_local_expr(tokens, item_start, item_end, locals, ctx)) {
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

pub fn count_agg_literal_items(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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

pub fn emit_storage_payload_ptr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    try storage_wat.emit_storage_payload_ptr(allocator, out, name);
}

pub fn emit_storage_payload_ptr_with_indent(allocator: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, indent: []const u8) !void {
    try storage_wat.emit_storage_payload_ptr_with_indent(allocator, out, name, indent);
}

pub fn emit_storage_content_comparison_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) return false;
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const cmp_ty = infer_storage_content_comparison_type(tokens, args_start, first_end, second_start, second_end, locals, ctx) orelse return false;
    if (try emit_managed_payload_storage_content_comparison_call(allocator, tokens, args_start, first_end, second_start, second_end, cmp_ty, call_name, locals, ctx, out)) {
        return true;
    }
    if (!try codegen_callbacks.emit_expr(allocator, tokens, args_start, first_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    if (!try codegen_callbacks.emit_expr(allocator, tokens, second_start, second_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try out.appendSlice(allocator, "    call $__storage_equal_u8\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

pub fn emit_managed_payload_storage_content_comparison_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, left_start: usize, left_end: usize, right_start: usize, right_end: usize, cmp_ty: []const u8, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const elem_ty = storage_elem_type_from_name(cmp_ty) orelse return false;
    const nested_elem_ty = managed_payload_elem_type_from_name(elem_ty) orelse return false;
    if (!std.mem.eql(u8, nested_elem_ty, "u8")) return false;

    if (!try codegen_callbacks.emit_expr(allocator, tokens, left_start, left_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    if (!try codegen_callbacks.emit_expr(allocator, tokens, right_start, right_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});

    try appendFmt(allocator, out, "    i32.const 0\n    local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try appendFmt(allocator, out, "    i32.const 1\n    local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "    block $storage_managed_eq_done\n");
    try emit_storage_len_ptr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try out.appendSlice(allocator, "      i32.load\n");
    try emit_storage_len_ptr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
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
    try emit_storage_len_ptr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try out.appendSlice(allocator,
        \\        i32.load
        \\        i32.ge_u
        \\        br_if $storage_managed_eq_done
        \\
    );
    try emit_storage_data_ptr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\        i32.const 4
        \\        i32.mul
        \\        i32.add
        \\        i32.load
        \\
    );
    try emit_storage_data_ptr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
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

pub fn emit_storage_ptr_len_host_arg(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, host_import: HostImport, param_idx: usize, out: *std.ArrayList(u8)) !bool {
    if (!hostParamIsPtrLen(host_import, param_idx)) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return false;
    if (tokens[range.start].kind != .ident) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emit_storage_data_ptr(allocator, out, tokens[range.start].lexeme);
    try emit_storage_len_ptr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

pub fn emit_tuple_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!is_tuple_type_name(expected_ty)) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const tuple_local = findStructLocal(locals.struct_locals.items, tokens[range.start].lexeme) orelse return false;
        if (!std.mem.eql(u8, tuple_local.ty, expected_ty)) return false;
        try emitTupleLocalGet(allocator, tuple_local.name, expected_ty, ctx, out);
        return true;
    }

    const open_brace = struct_literal_open_rhs(tokens, range.start, range.end) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", range.end) catch return false;
    if (close_brace + 1 != range.end) return false;

    const literal_ty = compactTokenText(allocator, tokens, range.start, open_brace) catch return false;
    defer allocator.free(literal_ty);
    if (!std.mem.eql(u8, literal_ty, expected_ty)) return false;

    const arity = tuple_arity(expected_ty) orelse return false;
    var expr_start = open_brace + 1;
    var idx: usize = 0;
    while (expr_start < close_brace) {
        const expr_end = findArgEnd(tokens, expr_start, close_brace);
        if (idx >= arity) return error.NoMatchingCall;
        const elem_ty = tuple_element_type_at(expected_ty, idx) orelse return error.UnsupportedLowering;
        if (!try codegen_callbacks.emit_expr(allocator, tokens, expr_start, expr_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
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

pub fn emit_empty_storage_u8_value(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try storage_wat.emit_empty_storage_u8_value(allocator, out);
}

pub fn emit_empty_storage_for_elem_type(allocator: std.mem.Allocator, elem_ty: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    const type_id = storage_type_id_for_element(elem_ty, ctx);
    try storage_wat.emit_empty_storage_with_type_id(allocator, out, type_id, "    ");
}

pub fn emit_number_const(allocator: std.mem.Allocator, ctx: CodegenContext, out: *std.ArrayList(u8), lexeme: []const u8, ty: []const u8) !void {
    try appendFmt(allocator, out, "    {s}.const {s}\n", .{ codegen_wasm_type(ctx, ty), lexeme });
}

pub fn emit_tuple_field_path_get_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, first_end: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const field_ty = tuple_field_path_type(tokens, start_idx, end_idx, first_end, locals, ctx) orelse return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    const index_start = field_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    const elem_info = tupleGetElementInfo(tokens, index_start, index_end, field_ty) orelse return false;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const field_name = publicDeclName(tokens[field_start].lexeme);
    try appendFmt(allocator, out, "    local.get ${s}.{s}.{d}\n", .{ struct_local.name, field_name, elem_info.index });
    if (is_managed_local_type(elem_info.ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}

pub fn find_struct_literal_field(
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
        const field_end = find_struct_literal_field_end(tokens, assign_idx + 1, end_idx);
        if (std.mem.eql(u8, publicDeclName(tokens[field_start].lexeme), field_name)) {
            return .{ .value_start = assign_idx + 1, .value_end = field_end };
        }
        field_start = field_end;
        if (field_start < end_idx and tokEq(tokens[field_start], ",")) field_start += 1;
    }
    return null;
}

pub fn is_struct_literal_rhs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return struct_literal_open_rhs(tokens, start_idx, end_idx) != null;
}

pub fn find_struct_literal_field_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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

pub fn direct_managed_last_use_move_source(
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
    if (has_registered_defer_stmt(tokens, defer_ctx)) return null;
    const actual_name = direct_managed_local_expr_name(tokens, start_idx, end_idx, locals, ctx) orelse return null;
    const origin = findLocalOrigin(locals.locals.items, source_name) orelse .unknown;
    if (token_range_uses_ident(tokens, end_idx, body_end, source_name)) return null;
    return .{
        .source_name = source_name,
        .actual_name = actual_name,
        .origin = origin,
    };
}

pub fn has_registered_defer_stmt(tokens: []const lexer.Token, defer_ctx: ?*const DeferContext) bool {
    var cursor = defer_ctx;
    while (cursor) |scope| {
        const scan_end = @min(scope.registered_end_idx, scope.end_idx);
        var i = scope.start_idx;
        while (i < scan_end) {
            const stmt_end = findStmtEnd(tokens, i, scope.end_idx);
            if (is_defer_stmt(tokens, i, stmt_end)) return true;
            i = stmt_end;
        }
        cursor = scope.parent;
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

pub fn is_defer_stmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return start_idx + 1 < end_idx and tokEq(tokens[start_idx], "defer");
}

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

pub fn emit_managed_handle_call_expr_with_move_context(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != 1) return false;
    if (!std.mem.eql(u8, func.results[0], expected_ty)) return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    return try codegen_callbacks.emit_user_func_call_with_move_context(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out);
}

pub fn emit_storage_handle_binding_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, body_end: usize, allow_last_use_move: bool, expected_ty: []const u8, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!std.mem.eql(u8, infer_expr_type(tokens, start_idx, end_idx, locals, ctx) orelse "", expected_ty)) return false;
    const move_ctx = if (allow_last_use_move) CallLastUseMoveContext{
        .body_start = body_start,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
        .allow_field_read_move = true,
    } else null;
    if (!try codegen_callbacks.emit_expr_with_move_context(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, if (move_ctx) |*ctx_info| ctx_info else null, out)) return false;
    return true;
}

pub fn emit_tuple_call_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, tuple_local: StructLocal, out: *std.ArrayList(u8)) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
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
    if (!try codegen_callbacks.emit_user_func_call_with_move_context(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    try emitTupleLocalSet(allocator, tuple_local.name, tuple_local.ty, ctx, out);
    return true;
}
