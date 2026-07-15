//! Expression / call emit dispatch.
//! Storage / tuple emit and pack helpers.

const std = @import("std");
const function_body_wat = @import("function_body_wat.zig");
const backend_ir = @import("backend_ir.zig");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");
const NilComparisonNarrowing = model.NilComparisonNarrowing;
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const emitWasiResultListU8StatusMultiAssignment = gen_wasi_emit.emitWasiResultListU8StatusMultiAssignment;
const emitWasiResultReadMultiAssignment = gen_wasi_emit.emitWasiResultReadMultiAssignment;
const emitWasiResultUnitStatusMultiAssignment = gen_wasi_emit.emitWasiResultUnitStatusMultiAssignment;
const emitWasiResultDescriptorStatusMultiAssignment = gen_wasi_emit.emitWasiResultDescriptorStatusMultiAssignment;
const emitWasiResultU64StreamStatusMultiAssignment = gen_wasi_emit.emitWasiResultU64StreamStatusMultiAssignment;
const emitWasiResultFilesizeMultiAssignment = gen_wasi_emit.emitWasiResultFilesizeMultiAssignment;
const gen_hooks = @import("gen_hooks.zig");
const codegen_collect_body = @import("codegen_collect_body.zig");
const collect_body_locals = codegen_collect_body.collect_body_locals;
const collect_callback_call_args = codegen_collect_body.collect_callback_call_args;
const emit_self_tail_loop_local_reset = codegen_collect_body.emit_self_tail_loop_local_reset;
const func_variadic_param_index = codegen_collect_body.func_variadic_param_index;
const multi_result_lhs_for_item = codegen_collect_body.multi_result_lhs_for_item;
const appendLoopSourceStorageLocal = context.appendLoopSourceStorageLocal;
const parseUnionTypeLayout = gen_collect_util.parseUnionTypeLayout;
const InferredUnionBinding = model.InferredUnionBinding;
const findUnionLocalExact = context.findUnionLocalExact;
const NUMERIC_SELECT_RIGHT_TMP_I32 = constants.NUMERIC_SELECT_RIGHT_TMP_I32;
const NUMERIC_SELECT_LEFT_TMP_I32 = constants.NUMERIC_SELECT_LEFT_TMP_I32;
const NUMERIC_SELECT_RIGHT_TMP_I64 = constants.NUMERIC_SELECT_RIGHT_TMP_I64;
const NUMERIC_SELECT_LEFT_TMP_I64 = constants.NUMERIC_SELECT_LEFT_TMP_I64;
const VARIADIC_PACK_TMP_LOCAL = constants.VARIADIC_PACK_TMP_LOCAL;
const NO_RESULT_ITEMS = model.NO_RESULT_ITEMS;
const NumericSelectTemps = model.NumericSelectTemps;
const wasmType = gen_wasi_emit.wasmType;
const codegenScalarType = gen_wasi_emit.codegenScalarType;
const MultiResultLhs = model.MultiResultLhs;
const SourceOrigin = model.SourceOrigin;
const findPayloadEnumDecl = gen_import.findPayloadEnumDecl;
const findStartFunc = codegen_tokens.find_start_func;
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
const EMPTY_LOCAL_SET = LocalSet{};
const DeferItem = context.DeferItem;
const SelfTailTco = context.SelfTailTco;
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

const gen_storage = @import("gen_storage.zig");
const ManagedPayloadBinding = gen_storage.ManagedPayloadBinding;
const gen_struct = @import("gen_struct.zig");
const gen_union_emit = @import("gen_union_emit.zig");
const gen_ctrl = @import("gen_ctrl.zig");
const gen_ownership = @import("gen_ownership.zig");
const emitStorageBinding = gen_storage.emitStorageBinding;
const emitStorageHandleAssignmentExpr = gen_storage.emitStorageHandleAssignmentExpr;
const emitTupleBinding = gen_storage.emitTupleBinding;
const emitStorageAssignment = gen_storage.emitStorageAssignment;
const stmtContainsStorageAggLiteral = gen_storage.stmtContainsStorageAggLiteral;
const emitStorageAggReturnValue = gen_storage.emitStorageAggReturnValue;
const emitTupleReturnLocal = gen_storage.emitTupleReturnLocal;
const emitTupleReturnExpr = gen_storage.emitTupleReturnExpr;
const emitStorageU8StringLiteral = gen_storage.emitStorageU8StringLiteral;
const emitStorageU8StringLiteralValue = gen_storage.emitStorageU8StringLiteralValue;
const emitStorageU8RawStringValue = gen_storage.emitStorageU8RawStringValue;
const emitStorageU8StringLiteralIntoLocal = gen_storage.emitStorageU8StringLiteralIntoLocal;
const emitStorageAggLiteral = gen_storage.emitStorageAggLiteral;
const isStorageAggLiteralExpr = gen_storage.isStorageAggLiteralExpr;
const countAggLiteralItems = gen_storage.countAggLiteralItems;
const emitStoragePayloadPtr = gen_storage.emitStoragePayloadPtr;
const emitStorageLenPtrWithIndent = gen_storage.emitStorageLenPtrWithIndent;
const emitStorageCapPtr = gen_storage.emitStorageCapPtr;
const emitStorageCapPtrWithIndent = gen_storage.emitStorageCapPtrWithIndent;
const emitStoragePayloadPtrWithIndent = gen_storage.emitStoragePayloadPtrWithIndent;
const emitTupleLocalSet = gen_storage.emitTupleLocalSet;
const emitTupleLocalGet = gen_storage.emitTupleLocalGet;
const emitTupleGetBinding = gen_storage.emitTupleGetBinding;
const emitStorageContentComparisonCall = gen_storage.emitStorageContentComparisonCall;
const emitManagedPayloadStorageContentComparisonCall = gen_storage.emitManagedPayloadStorageContentComparisonCall;
const inferStorageContentComparisonType = gen_storage.inferStorageContentComparisonType;
const storageContentArgCompatible = gen_storage.storageContentArgCompatible;
const isManagedPayloadComparableType = gen_storage.isManagedPayloadComparableType;
const emitStoragePtrLenHostArg = gen_storage.emitStoragePtrLenHostArg;
const emitTupleExpr = gen_storage.emitTupleExpr;
const storageBindingElemType = gen_storage.storageBindingElemType;
const managedPayloadBinding = gen_storage.managedPayloadBinding;
const parseStorageType = gen_storage.parseStorageType;
const emitStorageBoundsCheck = gen_storage.emitStorageBoundsCheck;
const emitStorageWriteExpr = gen_storage.emitStorageWriteExpr;
const emitStorageSetExpr = gen_storage.emitStorageSetExpr;
const emitStoragePutCall = gen_storage.emitStoragePutCall;
const emitStoragePutExpr = gen_storage.emitStoragePutExpr;
const emitStoragePutSpreadCall = gen_storage.emitStoragePutSpreadCall;
const emitStorageSetScalarCall = gen_storage.emitStorageSetScalarCall;
const emitStoragePutSpreadScalarElement = gen_storage.emitStoragePutSpreadScalarElement;
const emitStoragePutScalarCall = gen_storage.emitStoragePutScalarCall;
const emitStorageCloneCurrentLen = gen_storage.emitStorageCloneCurrentLen;
const emitStorageCloneCurrentLenForElem = gen_storage.emitStorageCloneCurrentLenForElem;
const emitStorageCloneManagedCurrentLen = gen_storage.emitStorageCloneManagedCurrentLen;
const emitStorageCloneManagedWithLenLocal = gen_storage.emitStorageCloneManagedWithLenLocal;
const emitStorageIncCopiedManagedElements = gen_storage.emitStorageIncCopiedManagedElements;
const emitStorageCloneWithLenLocal = gen_storage.emitStorageCloneWithLenLocal;
const emitStorageCloneWithLenLocalForElem = gen_storage.emitStorageCloneWithLenLocalForElem;
const emitStorageCloneWithLenLocalTyped = gen_storage.emitStorageCloneWithLenLocalTyped;
const emitStorageIncCopiedPackElements = gen_storage.emitStorageIncCopiedPackElements;
const emitStorageElementPtrFromLocal = gen_storage.emitStorageElementPtrFromLocal;
const emitStorageElementPtrFromLocalWithIndent = gen_storage.emitStorageElementPtrFromLocalWithIndent;
const emitStorageAliasProtect = gen_storage.emitStorageAliasProtect;
const emitStorageAliasRelease = gen_storage.emitStorageAliasRelease;
const emitEmptyStorageU8Value = gen_storage.emitEmptyStorageU8Value;
const emitEmptyStorageForElemType = gen_storage.emitEmptyStorageForElemType;
const storageElementByteWidthForType = gen_storage.storageElementByteWidthForType;
const tuplePackSpillLocal = gen_storage.tuplePackSpillLocal;
const appendStoreTupleScalarLeavesFromStack = gen_storage.appendStoreTupleScalarLeavesFromStack;
const appendStoreTupleScalarLeavesFromStackCtx = gen_storage.appendStoreTupleScalarLeavesFromStackCtx;
const appendStoreTupleLeavesOwningFromStack = gen_storage.appendStoreTupleLeavesOwningFromStack;
const appendStoreTupleLeavesOwningFromStackCtx = gen_storage.appendStoreTupleLeavesOwningFromStackCtx;
const appendIncManagedTupleLeavesOnStackCtx = gen_storage.appendIncManagedTupleLeavesOnStackCtx;
const appendLoadTupleScalarLeavesToStack = gen_storage.appendLoadTupleScalarLeavesToStack;
const appendLoadTupleScalarLeavesToStackCtx = gen_storage.appendLoadTupleScalarLeavesToStackCtx;
const appendLoadTupleLeavesOwningToStack = gen_storage.appendLoadTupleLeavesOwningToStack;
const appendLoadTupleLeavesOwningToStackCtx = gen_storage.appendLoadTupleLeavesOwningToStackCtx;
const appendLoadTupleElementFromPackedBaseCtx = gen_storage.appendLoadTupleElementFromPackedBaseCtx;
const appendLoadTupleLeafTypesOfStructToStack = gen_storage.appendLoadTupleLeafTypesOfStructToStack;
const appendLoadTupleElementOwningFromPackedBase = gen_storage.appendLoadTupleElementOwningFromPackedBase;
const emitIncManagedTupleLeavesAtBase = gen_storage.emitIncManagedTupleLeavesAtBase;
const emitDecManagedTupleLeavesAtBase = gen_storage.emitDecManagedTupleLeavesAtBase;
const emitNumberConst = gen_storage.emitNumberConst;
const appendStoreForPayloadType = gen_storage.appendStoreForPayloadType;
const appendStoreForPayloadTypeWithIndent = gen_storage.appendStoreForPayloadTypeWithIndent;
const appendLoadForPayloadTypeWithIndent = gen_storage.appendLoadForPayloadTypeWithIndent;
const emitTupleFieldPathGetCall = gen_storage.emitTupleFieldPathGetCall;
const emitPureScalarStructLocalSet = gen_storage.emitPureScalarStructLocalSet;
const emitPureScalarStructLocalGet = gen_storage.emitPureScalarStructLocalGet;
const singleTupleResultItem = gen_storage.singleTupleResultItem;
const isDirectManagedLocalExpr = gen_storage.isDirectManagedLocalExpr;
const storagePackLayoutForElem = gen_storage.storagePackLayoutForElem;
const tupleElementPackOffsetWithStructs = gen_storage.tupleElementPackOffsetWithStructs;
const tupleFieldPathType = gen_storage.tupleFieldPathType;
const findStructLiteralField = gen_storage.findStructLiteralField;
const substituteStructFieldType = gen_storage.substituteStructFieldType;
const isStructLiteralRhs = gen_storage.isStructLiteralRhs;
const emitReplaceStoragePutSourceTmp = gen_storage.emitReplaceStoragePutSourceTmp;
const directManagedLocalExprName = gen_storage.directManagedLocalExprName;
const emitOverwriteReleaseManagedLocal = gen_storage.emitOverwriteReleaseManagedLocal;
const findLocalFieldType = gen_storage.findLocalFieldType;
const tupleGetElementInfo = gen_storage.tupleGetElementInfo;
const findFuncDeclForCallHead = gen_storage.findFuncDeclForCallHead;
const inferExprType = gen_storage.inferExprType;
const findStructLiteralFieldEnd = gen_storage.findStructLiteralFieldEnd;
const findStructFieldType = gen_storage.findStructFieldType;
const localFieldNameMatches = gen_storage.localFieldNameMatches;
const directManagedLastUseMoveSource = gen_storage.directManagedLastUseMoveSource;
const structLiteralOpenRhs = gen_storage.structLiteralOpenRhs;
const unionPayloadLocalNameFromLocals = gen_storage.unionPayloadLocalNameFromLocals;
const substituteGenericType = gen_storage.substituteGenericType;
const isUnionPayloadLocalName = gen_storage.isUnionPayloadLocalName;
const findCallbackCallArg = gen_storage.findCallbackCallArg;
const appendTupleLocalFieldsBorrowed = gen_storage.appendTupleLocalFieldsBorrowed;
const findFuncDeclForCall = gen_storage.findFuncDeclForCall;
const findLocalName = gen_storage.findLocalName;
const emitStorageSetCall = gen_storage.emitStorageSetCall;
const emitStoragePutOneCall = gen_storage.emitStoragePutOneCall;
const callExplicitTypeArgsMatchBindings = gen_storage.callExplicitTypeArgsMatchBindings;
const callArgsMatchFuncParams = gen_storage.callArgsMatchFuncParams;
const hasRegisteredDeferStmt = gen_storage.hasRegisteredDeferStmt;
const appendBorrowedLocalField = gen_storage.appendBorrowedLocalField;
const tokenRangeUsesIdent = gen_storage.tokenRangeUsesIdent;
const shouldInferBoolSpecialCall = gen_storage.shouldInferBoolSpecialCall;
const isDeferStmt = gen_storage.isDeferStmt;
const callArgMatchesCallbackShape = gen_storage.callArgMatchesCallbackShape;
const emitStorageSetManagedCall = gen_storage.emitStorageSetManagedCall;
const emitStoragePutManagedCall = gen_storage.emitStoragePutManagedCall;
const emitManagedStorageValue = gen_storage.emitManagedStorageValue;
const inferScalarAsCallType = gen_storage.inferScalarAsCallType;
const findCallbackBinding = gen_storage.findCallbackBinding;
const scalarAsTargetType = gen_storage.scalarAsTargetType;
const callArgMatchesConcreteCallbackBinding = gen_storage.callArgMatchesConcreteCallbackBinding;
const isScalarAsTargetTypeName = gen_storage.isScalarAsTargetTypeName;
const inferSetCallType = gen_storage.inferSetCallType;
const callbackBindingsHaveSameShape = gen_storage.callbackBindingsHaveSameShape;
const callArgMatchesParam = gen_storage.callArgMatchesParam;
const inferPutCallType = gen_storage.inferPutCallType;
const callArgsMatchVariadicTail = gen_storage.callArgsMatchVariadicTail;
const callArgMatchesUnionParam = gen_storage.callArgMatchesUnionParam;
const unionTypeNameHasBranch = gen_storage.unionTypeNameHasBranch;
const inferFieldGetCallType = gen_storage.inferFieldGetCallType;
const funcVariadicElemType = gen_storage.funcVariadicElemType;
const inferFieldSetCallType = gen_storage.inferFieldSetCallType;
const findFieldMetaLocal = gen_storage.findFieldMetaLocal;
const structLiteralExprMatchesType = gen_storage.structLiteralExprMatchesType;
const inferGetCallType = gen_storage.inferGetCallType;
const lambdaExprShape = gen_storage.lambdaExprShape;
const lambdaParamCount = gen_storage.lambdaParamCount;
const callbackBindingHasSameConcreteArg = gen_storage.callbackBindingHasSameConcreteArg;
const valueEnumBranchValue = gen_storage.valueEnumBranchValue;
const inferTupleFieldPathGetType = gen_storage.inferTupleFieldPathGetType;
const appendManagedStructFieldMetaLocal = gen_storage.appendManagedStructFieldMetaLocal;
const fieldFromMeta = gen_storage.fieldFromMeta;
const findStructField = gen_storage.findStructField;
const unionLocalDefaultPayloadType = gen_storage.unionLocalDefaultPayloadType;
const unionLocalDefaultStructPayload = gen_storage.unionLocalDefaultStructPayload;
const findNarrowedUnionType = gen_storage.findNarrowedUnionType;
const isDotIdent = gen_storage.isDotIdent;
const isArrowAt = gen_storage.isArrowAt;
const lambdaBodyStart = gen_storage.lambdaBodyStart;
const lambdaParamTypeName = gen_storage.lambdaParamTypeName;
const lambdaExplicitReturnType = gen_storage.lambdaExplicitReturnType;
const appendTypedLocalWithDecl = gen_storage.appendTypedLocalWithDecl;
const appendTypedLocal = gen_storage.appendTypedLocal;
const inferLambdaExprReturnType = gen_storage.inferLambdaExprReturnType;
const cloneLocalSet = gen_storage.cloneLocalSet;
const callbackFunctionMatchesShape = gen_storage.callbackFunctionMatchesShape;
const callbackLambdaReturnMatchesShape = gen_storage.callbackLambdaReturnMatchesShape;
const findCallbackRefFunc = gen_storage.findCallbackRefFunc;
const lambdaExplicitTypesMatchShape = gen_storage.lambdaExplicitTypesMatchShape;
const typeBaseName = gen_storage.typeBaseName;
const valueEnumTypeMatchesImportAlias = gen_storage.valueEnumTypeMatchesImportAlias;
const findValueEnumBranchValue = gen_storage.findValueEnumBranchValue;
const valueEnumBranchValueInLine = gen_storage.valueEnumBranchValueInLine;
const valueEnumSourceMatchesImport = gen_storage.valueEnumSourceMatchesImport;
const managedPayloadElemTypeFromName = gen_storage.managedPayloadElemTypeFromName;
const absResultType = gen_storage.absResultType;
const inferFirstArgTypeOrDefaultS32 = gen_storage.inferFirstArgTypeOrDefaultS32;
const wasiDoResultType = gen_storage.wasiDoResultType;
const memoryLoadResultType = gen_storage.memoryLoadResultType;
const inferPathGetCallType = gen_storage.inferPathGetCallType;
const inferManagedStructExprFieldType = gen_storage.inferManagedStructExprFieldType;
const findConcreteStructFieldTypeNoAlloc = gen_storage.findConcreteStructFieldTypeNoAlloc;
const genericTypeArgAt = gen_storage.genericTypeArgAt;
const emitManagedHandleCallExprWithMoveContext = gen_storage.emitManagedHandleCallExprWithMoveContext;
const emitStorageHandleBindingExpr = gen_storage.emitStorageHandleBindingExpr;
const emitTupleCallBinding = gen_storage.emitTupleCallBinding;
const emitFieldReflectionBody = gen_struct.emitFieldReflectionBody;
const emitFieldReflectionLoopBlock = gen_struct.emitFieldReflectionLoopBlock;
const emitManagedStructFieldSet = gen_struct.emitManagedStructFieldSet;
const emitStructBinding = gen_struct.emitStructBinding;
const emitStructFieldValue = gen_struct.emitStructFieldValue;
const emitUnmanagedStructCallBinding = gen_struct.emitUnmanagedStructCallBinding;
const emitUnmanagedStructErrorUnionReturn = gen_struct.emitUnmanagedStructErrorUnionReturn;
const emitUserFuncArg = gen_struct.emitUserFuncArg;
const emitStructFieldMetaSetAssignment = gen_struct.emitStructFieldMetaSetAssignment;
const emitStructLiteralExpr = gen_struct.emitStructLiteralExpr;
const emitStructSetAssignment = gen_struct.emitStructSetAssignment;
const fieldStaticValuesEqual = gen_struct.fieldStaticValuesEqual;
const fieldReflectionLocalVisible = gen_struct.fieldReflectionLocalVisible;
const appendUnionPayloadLocalGet = gen_struct.appendUnionPayloadLocalGet;
const resolvedLocalName = gen_struct.resolvedLocalName;
const appendUnionTagLocalGet = gen_struct.appendUnionTagLocalGet;
const appendUnionTagLocalSet = gen_struct.appendUnionTagLocalSet;
const isManagedStructField = gen_struct.isManagedStructField;
const structLocalSourceName = gen_struct.structLocalSourceName;
const stmtContainsStructLiteralExpr = gen_struct.stmtContainsStructLiteralExpr;
const fieldReflectionLocalNamePrefix = gen_struct.fieldReflectionLocalNamePrefix;
const emitUnmanagedStructReturnLocal = gen_struct.emitUnmanagedStructReturnLocal;
const emitStructFieldLocalGet = gen_struct.emitStructFieldLocalGet;
const emitStructFieldLocalSet = gen_struct.emitStructFieldLocalSet;
const emitStructFieldsFromLocal = gen_struct.emitStructFieldsFromLocal;
const emitManagedStructSetBinding = gen_struct.emitManagedStructSetBinding;
const emitManagedStructFields = gen_struct.emitManagedStructFields;
const emitManagedStructCloneWithFieldSet = gen_struct.emitManagedStructCloneWithFieldSet;
const appendManagedStructFieldPtr = gen_struct.appendManagedStructFieldPtr;
const fieldReflectionIfParts = gen_struct.fieldReflectionIfParts;
const fieldStaticBoolExpr = gen_struct.fieldStaticBoolExpr;
const fieldStaticValue = gen_struct.fieldStaticValue;
const fieldVisibleFromTokens = gen_struct.fieldVisibleFromTokens;
const isPrivateFieldName = gen_struct.isPrivateFieldName;
const typedStructBinding = gen_struct.typedStructBinding;
const inferredStructBinding = gen_struct.inferredStructBinding;
const emitManagedStructExprFieldGet = gen_struct.emitManagedStructExprFieldGet;
const emitFieldReflectionIntrinsic = gen_struct.emitFieldReflectionIntrinsic;
const emitFieldGetCall = gen_struct.emitFieldGetCall;
const emitUnmanagedStructFieldGet = gen_struct.emitUnmanagedStructFieldGet;
const emitStructSetExpr = gen_struct.emitStructSetExpr;
const borrowedFieldMetaLocalSet = gen_struct.borrowedFieldMetaLocalSet;
const singleFieldMetaArg = gen_struct.singleFieldMetaArg;
const fieldGetLastUseMoveSource = gen_struct.fieldGetLastUseMoveSource;
const unmanagedStructErrorUnionResult = gen_struct.unmanagedStructErrorUnionResult;
const freshStructLiteralBindingStmtEnd = gen_struct.freshStructLiteralBindingStmtEnd;
const emitZeroValueForType = gen_struct.emitZeroValueForType;
const collectFieldReflectionBodyLocals = gen_struct.collectFieldReflectionBodyLocals;
const appendUnionPayloadLocalSet = gen_struct.appendUnionPayloadLocalSet;
const applyGuardReturnNilNarrowing = gen_struct.applyGuardReturnNilNarrowing;
const applyGuardReturnIsNarrowing = gen_struct.applyGuardReturnIsNarrowing;
const applyGuardLoopControlNarrowing = gen_struct.applyGuardLoopControlNarrowing;
const nilComparisonNarrowing = gen_struct.nilComparisonNarrowing;
const isComparisonNarrowing = gen_struct.isComparisonNarrowing;
const singleIdentExpr = gen_struct.singleIdentExpr;
const singleNilExpr = gen_struct.singleNilExpr;
const unionLocalSingleNonNilPayloadType = gen_struct.unionLocalSingleNonNilPayloadType;
const unionLocalSingleRemainingPayloadType = gen_struct.unionLocalSingleRemainingPayloadType;
const trimTrailingComma = gen_struct.trimTrailingComma;
const applyCollectGuardReturnNarrowing = gen_struct.applyCollectGuardReturnNarrowing;
const mergeReturnCleanupLocals = gen_struct.mergeReturnCleanupLocals;
const fieldReflectionScopedCleanupLocalSet = gen_struct.fieldReflectionScopedCleanupLocalSet;
const emitUnionReturn = gen_union_emit.emitUnionReturn;
const emitUnionValue = gen_union_emit.emitUnionValue;
const emitUnionFieldGetValue = gen_union_emit.emitUnionFieldGetValue;
const emitUnionBranchValue = gen_union_emit.emitUnionBranchValue;
const emitUnionBranchPayload = gen_union_emit.emitUnionBranchPayload;
const unionLayoutsAbiCompatible = gen_union_emit.unionLayoutsAbiCompatible;
const cloneUnionLayoutSubstituted = gen_union_emit.cloneUnionLayoutSubstituted;
const buildPayloadEnumUnionLayout = gen_union_emit.buildPayloadEnumUnionLayout;
const findUnionBranchByCompatibleType = gen_union_emit.findUnionBranchByCompatibleType;
const emitUnionStructPayloadForType = gen_union_emit.emitUnionStructPayloadForType;
const emitUnionIsCall = gen_union_emit.emitUnionIsCall;
const collectUnionIsTags = gen_union_emit.collectUnionIsTags;
const emitUnionNilComparison = gen_union_emit.emitUnionNilComparison;
const emitUnionExprTagAndDiscardPayload = gen_union_emit.emitUnionExprTagAndDiscardPayload;
const unionPayloadComparisonCallBranch = gen_union_emit.unionPayloadComparisonCallBranch;
const emitUnionErrorBranchComparison = gen_union_emit.emitUnionErrorBranchComparison;
const errorBranchValueForComparison = gen_union_emit.errorBranchValueForComparison;
const emitUnionLocalPayloadForType = gen_union_emit.emitUnionLocalPayloadForType;
const emitUnionBinding = gen_union_emit.emitUnionBinding;
const emitUnionStructFieldGetCall = gen_union_emit.emitUnionStructFieldGetCall;
const importedErrorBranchValue = gen_union_emit.importedErrorBranchValue;
const collectUnionReturnMoveNames = gen_union_emit.collectUnionReturnMoveNames;
const unionLayoutHasSinglePayloadAbiType = gen_union_emit.unionLayoutHasSinglePayloadAbiType;
const unionPayloadComparisonBranchForValue = gen_union_emit.unionPayloadComparisonBranchForValue;
const emitUnionPayloadComparisonCall = gen_union_emit.emitUnionPayloadComparisonCall;
const emitUnionPayloadComparisonLocal = gen_union_emit.emitUnionPayloadComparisonLocal;
const unionPayloadComparisonBranchForLocalValue = gen_union_emit.unionPayloadComparisonBranchForLocalValue;
const unionLocalSingleIdent = gen_union_emit.unionLocalSingleIdent;
const findStorageReadableLocalName = gen_union_emit.findStorageReadableLocalName;
const emitUnionStoragePayloadGetCall = gen_union_emit.emitUnionStoragePayloadGetCall;
const isCodegenScalarType = gen_union_emit.isCodegenScalarType;
const isUnsignedScalar = gen_union_emit.isUnsignedScalar;
const comparisonWasmOp = gen_union_emit.comparisonWasmOp;
const collectDirectBodyLocals = gen_ctrl.collectDirectBodyLocals;
const fieldReflectionLoopHeader = gen_ctrl.fieldReflectionLoopHeader;
const collectionLoopHeader = gen_ctrl.collectionLoopHeader;
const recvLoopHeader = gen_ctrl.recvLoopHeader;
const parseCollectionLoopBinds = gen_ctrl.parseCollectionLoopBinds;
const parseRecvLoopBinds = gen_ctrl.parseRecvLoopBinds;
const loopBindName = gen_ctrl.loopBindName;
const emitReturnStmt = gen_ctrl.emitReturnStmt;
const emitSelfTailReturn = gen_ctrl.emitSelfTailReturn;
const emitMultiResultReturnValues = gen_ctrl.emitMultiResultReturnValues;
const emitMultiResultReturnAbiValues = gen_ctrl.emitMultiResultReturnAbiValues;
const emitSingleReturnAbiValue = gen_ctrl.emitSingleReturnAbiValue;
const emitMultiResultReturnCall = gen_ctrl.emitMultiResultReturnCall;
const collectLoopControlFrames = gen_ctrl.collectLoopControlFrames;
const isDeadManagedAliasBinding = gen_ctrl.isDeadManagedAliasBinding;
const emitBody = gen_ctrl.emitBody;
const isCollectedTypedStorageBinding = gen_ctrl.isCollectedTypedStorageBinding;
const isDiscardAssignment = gen_ctrl.isDiscardAssignment;
const discardExprIsPureNoop = gen_ctrl.discardExprIsPureNoop;
const emitDiscardStackValue = gen_ctrl.emitDiscardStackValue;
const emitDiscardAssignment = gen_ctrl.emitDiscardAssignment;
const emitDeferCleanupStack = gen_ctrl.emitDeferCleanupStack;
const emitDeferCleanupStackThrough = gen_ctrl.emitDeferCleanupStackThrough;
const applyIfBlockFallthroughNarrowing = gen_ctrl.applyIfBlockFallthroughNarrowing;
const sameDeferScope = gen_ctrl.sameDeferScope;
const emitDeferredCleanupsForContext = gen_ctrl.emitDeferredCleanupsForContext;
const parseDeferItem = gen_ctrl.parseDeferItem;
const emitDeferCleanupItem = gen_ctrl.emitDeferCleanupItem;
const emitDeferCleanupCall = gen_ctrl.emitDeferCleanupCall;
const emitDeferCleanupBlock = gen_ctrl.emitDeferCleanupBlock;
const emitManagedLocalAssignment = gen_ctrl.emitManagedLocalAssignment;
const emitScalarCallExprWithMoveContext = gen_ctrl.emitScalarCallExprWithMoveContext;
const emitScalarAssignment = gen_ctrl.emitScalarAssignment;
const emitInferredScalarBinding = gen_ctrl.emitInferredScalarBinding;
const appendNilComparisonNarrowingForBranch = gen_ctrl.appendNilComparisonNarrowingForBranch;
const appendConditionNarrowingForBranch = gen_ctrl.appendConditionNarrowingForBranch;
const isHostImportCallExpr = gen_ctrl.isHostImportCallExpr;
const isWasiHostImportCallExpr = gen_ctrl.isWasiHostImportCallExpr;
const typedScalarBindingType = gen_ctrl.typedScalarBindingType;
const inferredScalarBindingType = gen_ctrl.inferredScalarBindingType;
const isManagedLocalAssignmentStmt = gen_ctrl.isManagedLocalAssignmentStmt;
const typedStructBindingDecl = gen_ctrl.typedStructBindingDecl;
const inferredStructCtorBinding = gen_ctrl.inferredStructCtorBinding;
const clearNarrowedUnionLocalsForAssignments = gen_ctrl.clearNarrowedUnionLocalsForAssignments;
const clearNarrowedUnionLocal = gen_ctrl.clearNarrowedUnionLocal;
const emitGuardReturnIf = gen_ctrl.emitGuardReturnIf;
const emitLoopBlock = gen_ctrl.emitLoopBlock;
const emitCollectionLoopBlock = gen_ctrl.emitCollectionLoopBlock;
const emitCollectionLoopBindings = gen_ctrl.emitCollectionLoopBindings;
const emitRecvLoopBlock = gen_ctrl.emitRecvLoopBlock;
const emitRecvLoopBindings = gen_ctrl.emitRecvLoopBindings;
const emitLoopControlStmt = gen_ctrl.emitLoopControlStmt;
const emitGuardLoopControlIf = gen_ctrl.emitGuardLoopControlIf;
const emitLoopControlJump = gen_ctrl.emitLoopControlJump;
const validLoopControlTail = gen_ctrl.validLoopControlTail;
const resolveLoopControl = gen_ctrl.resolveLoopControl;
const emitLoopControlReleaseChain = gen_ctrl.emitLoopControlReleaseChain;
const emitIfBlock = gen_ctrl.emitIfBlock;
const isCodegenScalarOrErrorType = gen_ctrl.isCodegenScalarOrErrorType;
const emitReleaseManagedLocals = gen_ownership.emitReleaseManagedLocals;
const emitReleaseManagedLocalsExcept = gen_ownership.emitReleaseManagedLocalsExcept;
const emitReleaseManagedLocalsExceptMany = gen_ownership.emitReleaseManagedLocalsExceptMany;
const emitFallthroughReleaseManagedLocals = gen_ownership.emitFallthroughReleaseManagedLocals;
const emitBlockReleaseManagedLocals = gen_ownership.emitBlockReleaseManagedLocals;
const hasManagedLocals = gen_ownership.hasManagedLocals;
const managedLocalKindForType = gen_ownership.managedLocalKindForType;
const collectManagedOwnershipLocals = gen_ownership.collectManagedOwnershipLocals;
const buildReturnOwnershipPlan = gen_ownership.buildReturnOwnershipPlan;
const buildGuardReturnOwnershipPlan = gen_ownership.buildGuardReturnOwnershipPlan;
const buildFallthroughOwnershipPlan = gen_ownership.buildFallthroughOwnershipPlan;
const buildBlockOwnershipPlan = gen_ownership.buildBlockOwnershipPlan;
const emitOwnershipReleasePlan = gen_ownership.emitOwnershipReleasePlan;
const bodyEndsWithPlainReturn = gen_ownership.bodyEndsWithPlainReturn;
const bodyCanReachEnd = gen_ownership.bodyCanReachEnd;
const stmtCanReachEnd = gen_ownership.stmtCanReachEnd;
const ifStmtCanReachEnd = gen_ownership.ifStmtCanReachEnd;
const loopStmtCanReachEnd = gen_ownership.loopStmtCanReachEnd;
const loopBodyCanBreakCurrentLoop = gen_ownership.loopBodyCanBreakCurrentLoop;
const stmtBreaksCurrentLoop = gen_ownership.stmtBreaksCurrentLoop;
const breakTargetsCurrentLoop = gen_ownership.breakTargetsCurrentLoop;
const tokenRangeContainsLabeledBreak = gen_ownership.tokenRangeContainsLabeledBreak;
const sameLoopControl = gen_ownership.sameLoopControl;
const findTopLevelGuardLoopControl = gen_ownership.findTopLevelGuardLoopControl;
const labelForLoopStart = gen_ownership.labelForLoopStart;
const previousLineStart = gen_ownership.previousLineStart;

pub const emitWasiRecordReturnCall = gen_wasi_emit.emitWasiRecordReturnCall;
pub const emitWasiRecordResultFields = gen_wasi_emit.emitWasiRecordResultFields;

pub fn appendStructFieldAbiParams(allocator: std.mem.Allocator, tokens: []const lexer.Token, out: *std.ArrayList(u8), base: []const u8, field: []const u8, field_ty: []const u8, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) !void {
    const field_name = publicDeclName(field);
    if (try parse_type_union_layout_from_name(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        for (layout.payload_tys, 0..) |payload_ty, idx| {
            try appendFmt(allocator, out, " (param ${s}.{s}.__union_payload_{d} {s})", .{
                base,
                field_name,
                idx,
                codegenWasmType(ctx, payload_ty),
            });
        }
        try appendFmt(allocator, out, " (param ${s}.{s}.__union_tag i32)", .{ base, field_name });
        return;
    }
    try appendFmt(allocator, out, " (param ${s}.{s} {s})", .{
        base,
        field_name,
        codegenWasmType(ctx, field_ty),
    });
}

pub fn emitStartFunc(allocator: std.mem.Allocator, tokens: []const lexer.Token, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const start_idx = findStartFunc(tokens) orelse return;
    const open_params = start_idx + 1;
    const close_params = try findMatching(tokens, open_params, "(", ")");
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse return;
    const close_body = try findMatching(tokens, open_body, "{", "}");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try collect_body_locals(allocator, tokens, open_body + 1, close_body, ctx, &locals);
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collectDirectBodyLocals(allocator, tokens, open_body + 1, close_body, ctx, &cleanup_locals);

    try function_body_wat.emitFuncOpen(allocator, out, "_start");
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        try function_body_wat.emitLocalDecl(allocator, out, local.name, codegenWasmType(ctx, local.ty));
    }
    const no_results: []const []const u8 = &.{};
    const root_defer = DeferContext{
        .parent = null,
        .start_idx = open_body + 1,
        .end_idx = close_body,
        .registered_end_idx = close_body,
    };
    var backend_ir_body = std.ArrayList(u8).empty;
    defer backend_ir_body.deinit(allocator);
    const emitted_backend_ir = try emitScalarNumericStartWithBackendIr(allocator, tokens, open_body + 1, close_body, &locals, ctx, &backend_ir_body);
    if (emitted_backend_ir) {
        try out.appendSlice(allocator, "    ;; backend-ir-lowering scalar-numeric-start\n");
        try out.appendSlice(allocator, backend_ir_body.items);
    }
    if (!emitted_backend_ir) {
        try gen_hooks.emitBody(allocator, tokens, open_body + 1, close_body, open_body + 1, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, ctx, no_results, NO_RESULT_ITEMS, null, null, null, &root_defer, null, null, out);
    }
    if (!bodyEndsWithPlainReturn(tokens, open_body + 1, close_body)) {
        try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, ctx, out);
    }
    try function_body_wat.emitFuncClose(allocator, out);
    try function_body_wat.emitFuncExport(allocator, out, "_start", "_start");
}

const BackendIrLocal = struct {
    name: []const u8,
    value: backend_ir.ValueId,
};

pub fn emitScalarNumericStartWithBackendIr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    var func = try backend_ir.Function.create(allocator, "_start_ir");
    defer func.deinit(allocator);
    const block_id = try func.addBlockId(allocator);

    var ir_locals = std.ArrayList(BackendIrLocal).empty;
    defer ir_locals.deinit(allocator);

    var i = start_idx;
    var saw_return = false;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (isPlainNilReturnStmt(tokens, i, stmt_end)) {
            try func.setTerminator(block_id, .ret);
            saw_return = true;
            i = stmt_end;
            continue;
        }

        const scalar_ty = typedScalarBindingType(tokens, i, stmt_end, ctx) orelse return false;
        if (!std.mem.eql(u8, scalar_ty, "i32")) return false;
        const eq_idx = findTopLevelToken(tokens, i + 1, stmt_end, "=") orelse return false;
        const target_source_name = tokens[i].lexeme;
        const target_name = resolvedLocalName(locals.locals.items, target_source_name);
        const value = func.allocValue();
        try func.setValueName(allocator, value, target_name);
        try ir_locals.append(allocator, .{ .name = target_source_name, .value = value });
        try ir_locals.append(allocator, .{ .name = target_name, .value = value });

        if (!try appendScalarNumericExprIr(allocator, tokens, eq_idx + 1, stmt_end, "i32", &func, block_id, ir_locals.items)) {
            return false;
        }
        try func.appendInstr(allocator, block_id, .{ .local_set = value });
        i = stmt_end;
    }
    if (!saw_return) return false;

    const body = try backend_ir.emitFunctionBodyWat(allocator, &func);
    defer allocator.free(body);
    try out.appendSlice(allocator, body);
    return true;
}

pub fn isPlainNilReturnStmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return start_idx + 1 == end_idx and tokEq(tokens[start_idx], "return");
}

pub fn appendScalarNumericExprIr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected_ty: []const u8, func: *backend_ir.Function, block_id: backend_ir.BlockId, ir_locals: []const BackendIrLocal) CodegenError!bool {
    if (!std.mem.eql(u8, expected_ty, "i32")) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (range.start + 1 == range.end) {
        const tok = tokens[range.start];
        if (tok.kind == .number) {
            const value = std.fmt.parseInt(i32, tok.lexeme, 0) catch return false;
            try func.appendInstr(allocator, block_id, .{ .const_value = .{ .i32 = value } });
            return true;
        }
        if (tok.kind == .ident) {
            const local = findBackendIrLocal(ir_locals, tok.lexeme) orelse return false;
            try func.appendInstr(allocator, block_id, .{ .local_get = local });
            return true;
        }
        return false;
    }

    const call_head = exprCallHead(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    const op = numericCoreIrOp(tokens[call_head.name_idx].lexeme) orelse return false;

    var arg_start = call_head.args_start;
    var emitted = false;
    while (arg_start < call_head.args_end) {
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        if (!try appendScalarNumericExprIr(allocator, tokens, arg_start, arg_end, expected_ty, func, block_id, ir_locals)) {
            return false;
        }
        if (emitted) {
            try func.appendInstr(allocator, block_id, .{ .numeric = .{ .ty = .i32, .op = op } });
        }
        emitted = true;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    return emitted;
}

pub fn findBackendIrLocal(ir_locals: []const BackendIrLocal, name: []const u8) ?backend_ir.ValueId {
    for (ir_locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local.value;
    }
    return null;
}

pub fn numericCoreIrOp(name: []const u8) ?backend_ir.NumericOp {
    if (std.mem.eql(u8, name, "add")) return .add;
    if (std.mem.eql(u8, name, "sub")) return .sub;
    if (std.mem.eql(u8, name, "mul")) return .mul;
    return null;
}

pub fn emitTestFuncs(allocator: std.mem.Allocator, tokens: []const lexer.Token, test_decls: []const test_runner.TestDecl, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    for (test_decls, 0..) |decl, idx| {
        try function_body_wat.emitCompiledTestOpen(allocator, out, idx, decl.name_lexeme);

        var locals = LocalSet{};
        defer locals.deinit(allocator);
        try collect_body_locals(allocator, tokens, decl.body_start, decl.body_end, ctx, &locals);
        var cleanup_locals = LocalSet{};
        defer cleanup_locals.deinit(allocator);
        try collectDirectBodyLocals(allocator, tokens, decl.body_start, decl.body_end, ctx, &cleanup_locals);

        for (locals.locals.items) |local| {
            if (!local.emit_decl) continue;
            try function_body_wat.emitLocalDecl(allocator, out, local.name, codegenWasmType(ctx, local.ty));
        }
        const no_results: []const []const u8 = &.{};
        const root_defer = DeferContext{
            .parent = null,
            .start_idx = decl.body_start,
            .end_idx = decl.body_end,
            .registered_end_idx = decl.body_end,
        };
        try gen_hooks.emitBody(allocator, tokens, decl.body_start, decl.body_end, decl.body_start, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, ctx, no_results, NO_RESULT_ITEMS, null, null, null, &root_defer, null, null, out);
        if (!bodyEndsWithPlainReturn(tokens, decl.body_start, decl.body_end)) {
            try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, ctx, out);
        }
        try out.appendSlice(allocator, "    unreachable\n");
        try function_body_wat.emitFuncClose(allocator, out);
        try function_body_wat.emitCompiledTestExport(allocator, out, idx);
    }
}

pub fn emitUserFuncs(allocator: std.mem.Allocator, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (funcHasCallbackParams(func) and func.callback_bindings.len == 0) continue;
        try emitUserFunc(allocator, func, ctx, out);
    }
}

pub fn emitUserFunc(allocator: std.mem.Allocator, func: FuncDecl, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    var func_ctx = ctx;
    func_ctx.type_bindings = func.type_bindings;
    func_ctx.callback_bindings = func.callback_bindings;
    var signature_owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (signature_owned_types.items) |owned| allocator.free(owned);
        signature_owned_types.deinit(allocator);
    }

    const tokens = func.tokens;
    try appendFmt(allocator, out, "  (func ${s}", .{func.name});
    for (func.params) |param| {
        if (param.callback != null) continue;
        const abi_ty = funcParamAbiType(param);
        if (try resolveUnionLayoutForTypeName(allocator, tokens, abi_ty, func_ctx, &signature_owned_types)) |layout| {
            defer freeUnionLayout(allocator, layout);
            for (layout.payload_tys, 0..) |payload_ty, idx| {
                try appendFmt(allocator, out, " (param ${s}.__union_payload_{d} {s})", .{
                    param.name,
                    idx,
                    codegenWasmType(func_ctx, payload_ty),
                });
            }
            try appendFmt(allocator, out, " (param ${s}.__union_tag i32)", .{param.name});
            continue;
        }
        if (findStructDecl(func_ctx.structs, abi_ty)) |decl| {
            if (findStructLayout(func_ctx.struct_layouts, abi_ty) == null) {
                try appendUnmanagedStructParamFields(allocator, tokens, out, param.name, decl, abi_ty, func_ctx, &signature_owned_types);
                continue;
            }
        }
        if (isTupleTypeName(abi_ty)) {
            try appendTupleParamAbi(allocator, out, param.name, abi_ty, func_ctx);
            continue;
        }
        try appendFmt(allocator, out, " (param ${s} {s})", .{ param.name, codegenWasmType(func_ctx, abi_ty) });
    }
    if (func.results.len != 0) {
        try out.appendSlice(allocator, " (result");
        for (func.results) |result| {
            try appendFmt(allocator, out, " {s}", .{codegenWasmType(func_ctx, result)});
        }
        try out.appendSlice(allocator, ")");
    }
    try out.appendSlice(allocator, "\n");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try appendFuncParamLocals(allocator, func, func_ctx, &locals);
    try collect_body_locals(allocator, tokens, func.body_start, func.body_end, func_ctx, &locals);
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try appendFuncParamLocals(allocator, func, func_ctx, &cleanup_locals);
    try collectDirectBodyLocals(allocator, tokens, func.body_start, func.body_end, func_ctx, &cleanup_locals);

    const self_tail_tco = try buildSelfTailTco(allocator, func, tokens, &locals, &cleanup_locals, func_ctx);
    defer if (self_tail_tco) |tco| allocator.free(tco.loop_label);

    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        try function_body_wat.emitLocalDecl(allocator, out, local.name, codegenWasmType(func_ctx, local.ty));
    }
    if (self_tail_tco) |tco| {
        for (tco.func.params) |param| {
            if (param.callback != null) continue;
            try appendFmt(allocator, out, "    (local $__tail_arg_{s} {s})\n", .{
                param.name,
                codegenWasmType(func_ctx, param.ty),
            });
        }
    }
    if (func.arrow) {
        if (func.results.len != 1) return error.NoMatchingCall;
        if (!try emitExpr(allocator, tokens, func.body_start, func.body_end, &locals, func_ctx, func.results[0], out)) {
            return error.NoMatchingCall;
        }
        try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, func_ctx, out);
        try out.appendSlice(allocator, "    return\n");
    } else {
        const root_defer = DeferContext{
            .parent = null,
            .start_idx = func.body_start,
            .end_idx = func.body_end,
            .registered_end_idx = func.body_end,
        };
        const can_reach_end = bodyCanReachEnd(tokens, func.body_start, func.body_end);
        if (self_tail_tco) |tco| {
            try appendFmt(allocator, out, "    loop ${s}\n", .{tco.loop_label});
            try emit_self_tail_loop_local_reset(allocator, tco.func, &locals, func_ctx, out);
            try gen_hooks.emitBody(allocator, tokens, func.body_start, func.body_end, func.body_start, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, func_ctx, func.results, func.result_items, func.result_struct, func.result_union, null, &root_defer, null, &tco, out);
            try out.appendSlice(allocator, "    end\n");
            if (func.results.len != 0 and !can_reach_end) {
                try out.appendSlice(allocator, "    unreachable\n");
            }
        } else {
            try gen_hooks.emitBody(allocator, tokens, func.body_start, func.body_end, func.body_start, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, func_ctx, func.results, func.result_items, func.result_struct, func.result_union, null, &root_defer, null, null, out);
        }
        if (!bodyEndsWithPlainReturn(tokens, func.body_start, func.body_end)) {
            try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, func_ctx, out);
            if (func.results.len != 0 and !can_reach_end) {
                try out.appendSlice(allocator, "    unreachable\n");
            }
        }
    }
    try function_body_wat.emitFuncClose(allocator, out);
}

pub fn buildSelfTailTco(allocator: std.mem.Allocator, func: FuncDecl, tokens: []const lexer.Token, locals: *const LocalSet, cleanup_locals: *const LocalSet, ctx: CodegenContext) !?SelfTailTco {
    if (func.arrow) return null;
    if (func.results.len != 1) return null;
    if (!isCodegenScalarType(ctx, func.results[0])) return null;
    if (!funcHasSelfTailReturn(tokens, func.body_start, func.body_end, func)) return null;
    if (funcHasDeferStmt(tokens, func.body_start, func.body_end)) return null;
    for (func.params) |param| {
        if (param.callback != null) return null;
        if (param.variadic) return null;
        if (!isCodegenScalarType(ctx, param.ty)) return null;
    }
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        if (!isCodegenScalarType(ctx, local.ty)) return null;
    }
    for (cleanup_locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        if (!isCodegenScalarType(ctx, local.ty)) return null;
    }
    if (hasManagedCleanupLocals(cleanup_locals, ctx)) return null;
    return .{
        .func = func,
        .loop_label = try std.fmt.allocPrint(allocator, "__tail_{s}", .{func.name}),
    };
}

pub fn funcHasSelfTailReturn(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, func: FuncDecl) bool {
    var i = start_idx;
    while (i < end_idx) {
        if (tokEq(tokens[i], "return")) {
            const stmt_end = findStmtEnd(tokens, i, end_idx);
            const range = trimParens(tokens, i + 1, stmt_end);
            const call_head = exprCallHead(tokens, range) orelse {
                i += 1;
                continue;
            };
            if (!call_head.is_intrinsic and same_callable_source_name(func.source_name, publicDeclName(tokens[call_head.name_idx].lexeme))) {
                return true;
            }
        }
        i += 1;
    }
    return false;
}

pub fn funcHasDeferStmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "defer")) return true;
    }
    return false;
}

pub fn hasManagedCleanupLocals(locals: *const LocalSet, ctx: CodegenContext) bool {
    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        if (managedLocalKindForType(local.ty, ctx) != null) return true;
    }
    return false;
}

pub fn resolveUnionLayoutForTypeName(allocator: std.mem.Allocator, tokens: []const lexer.Token, ty: []const u8, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) !?UnionLayout {
    if (findPayloadEnumDecl(ctx.payload_enums, ty)) |decl| {
        return try buildPayloadEnumUnionLayout(allocator, decl, tokens, ctx.structs, ctx.struct_layouts, owned_types);
    }
    return try parse_type_union_layout_from_name(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, owned_types);
}

pub fn factsSourceOrigin(origin: SourceOrigin) ownership_facts.SourceOrigin {
    return switch (origin) {
        .unknown => .unknown,
        .fresh_local => .fresh_local,
        .param_or_import => .param_or_import,
        .helper_shared => .helper_shared,
        .collection_value => .collection_value,
        .recv_value => .recv_value,
        .loop_source => .loop_source,
        .union_payload => .union_payload,
        .compiler_temp => .compiler_temp,
    };
}

pub fn directManagedCallLastUseMoveSource(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    move_ctx: CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?LastUseManagedMoveSource {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    const source_name = tokens[start_idx].lexeme;
    const actual_name = directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) orelse return null;
    const origin = findLocalOrigin(locals.locals.items, source_name) orelse .unknown;
    const after_arg_use = tokenRangeUsesIdent(tokens, end_idx, move_ctx.stmt_end, source_name);
    const after_stmt_use = tokenRangeUsesIdent(tokens, move_ctx.stmt_end, move_ctx.body_end, source_name);
    const candidate = ownership_facts.MoveCandidate{
        .kind = .call_arg,
        .source = .{
            .source_name = source_name,
            .actual_name = actual_name,
            .origin = factsSourceOrigin(origin),
        },
        .expr_range = .{ .start = start_idx, .end = end_idx },
        .context = .{
            .body = .{ .start = move_ctx.body_start, .end = move_ctx.body_end },
            .statement = .{ .end = move_ctx.stmt_end },
            .arg = .{ .start = start_idx, .end = end_idx },
            .defer_visible = hasRegisteredDeferStmt(tokens, move_ctx.defer_ctx),
            .allow_last_use_move = move_ctx.allow_last_use_move,
        },
        .future_use = .{
            .after_arg = if (after_arg_use) .{ .start = end_idx, .end = move_ctx.stmt_end } else null,
            .after_stmt = if (after_stmt_use) .{ .start = move_ctx.stmt_end, .end = move_ctx.body_end } else null,
        },
    };
    const decision = ownership_facts.decideCallArgMove(candidate);
    if (!decision.accepted) return null;
    return .{
        .source_name = source_name,
        .actual_name = actual_name,
        .origin = origin,
    };
}

pub fn directManagedUnionBindingCallMoveSource(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    args_end: usize,
    stmt_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    defer_ctx: ?*const DeferContext,
) ?LastUseManagedMoveSource {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (!allow_last_use_move) return null;
    if (hasRegisteredDeferStmt(tokens, defer_ctx)) return null;
    const source_name = tokens[start_idx].lexeme;
    const actual_name = directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) orelse return null;
    const origin = findLocalOrigin(locals.locals.items, source_name) orelse .unknown;
    if (tokenRangeUsesIdent(tokens, end_idx, args_end, source_name)) return null;
    if (tokenRangeUsesIdent(tokens, stmt_end, body_end, source_name)) return null;
    return .{
        .source_name = source_name,
        .actual_name = actual_name,
        .origin = origin,
    };
}

pub fn hasMoveSource(sources: []const LastUseManagedMoveSource, actual_name: []const u8) bool {
    for (sources) |source| {
        if (std.mem.eql(u8, source.actual_name, actual_name)) return true;
    }
    return false;
}

pub fn emitMultiResultAssignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    if (findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme)) |wasi_import| {
        if (try emitWasiResultUnitStatusMultiAssignment(allocator, tokens, start_idx, eq_idx, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, out, gen_hooks.emitExpr)) {
            return true;
        }
        if (try emitWasiResultFilesizeMultiAssignment(allocator, tokens, start_idx, eq_idx, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, out, gen_hooks.emitExpr)) {
            return true;
        }
        if (try emitWasiResultU64StreamStatusMultiAssignment(allocator, tokens, start_idx, eq_idx, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, out, gen_hooks.emitExpr)) {
            return true;
        }
        if (try emitWasiResultDescriptorStatusMultiAssignment(allocator, tokens, start_idx, eq_idx, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, out, gen_hooks.emitExpr)) {
            return true;
        }
        if (try emitWasiResultReadMultiAssignment(allocator, tokens, start_idx, eq_idx, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, out, gen_hooks.emitExpr)) {
            return true;
        }
        return try emitWasiResultListU8StatusMultiAssignment(allocator, tokens, start_idx, eq_idx, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, out, gen_hooks.emitExpr);
    }
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len <= 1) return false;
    if (func.result_items.len == 0) return false;

    var lhs_items = std.ArrayList(MultiResultLhs).empty;
    defer lhs_items.deinit(allocator);

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return error.NoMatchingCall;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return error.NoMatchingCall;
        const lhs = multi_result_lhs_for_item(tokens[lhs_start].lexeme, func.result_items[item_idx], locals, ctx) orelse return error.NoMatchingCall;
        try lhs_items.append(allocator, lhs);

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (item_idx != func.result_items.len) return error.NoMatchingCall;

    const move_ctx = CallLastUseMoveContext{
        .body_start = 0,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }

    var i = lhs_items.items.len;
    while (i > 0) {
        i -= 1;
        try emitMultiResultLhsSet(allocator, lhs_items.items[i], ctx, out);
    }
    return true;
}

pub fn emitMultiResultLhsSet(allocator: std.mem.Allocator, lhs: MultiResultLhs, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    switch (lhs.kind) {
        .scalar => try appendFmt(allocator, out, "    local.set ${s}\n", .{lhs.name}),
        .managed => {
            try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try emitReplaceManagedLocalFromTmp(allocator, lhs.name, out);
        },
        .union_value => {
            var idx = lhs.item.abi_len;
            while (idx > 0) {
                idx -= 1;
                if (idx == lhs.item.abi_len - 1) {
                    try appendUnionTagLocalSet(allocator, out, lhs.name);
                } else {
                    try appendUnionPayloadLocalSet(allocator, out, lhs.name, idx);
                }
            }
        },
        .unmanaged_struct => {
            const decl = findStructDecl(ctx.structs, lhs.ty) orelse return error.NoMatchingCall;
            if (decl.fields.len != lhs.item.abi_len) return error.NoMatchingCall;
            var idx = decl.fields.len;
            while (idx > 0) {
                idx -= 1;
                try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
                    lhs.name,
                    publicDeclName(decl.fields[idx].name),
                });
            }
        },
    }
}

pub fn emitExpr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: ?[]const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    return emitExprWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, null, out);
}

fn appendUnmanagedStructParamFields(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(u8),
    param_name: []const u8,
    decl: StructDecl,
    abi_ty: []const u8,
    func_ctx: CodegenContext,
    signature_owned_types: *std.ArrayList([]const u8),
) !void {
    for (decl.fields) |field| {
        const field_ty = try substituteStructFieldType(allocator, decl, abi_ty, field.ty, signature_owned_types);
        try appendStructFieldAbiParams(allocator, tokens, out, param_name, field.name, field_ty, func_ctx, signature_owned_types);
    }
}

fn emitIdentLiteralOrLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    tok: lexer.Token,
    expected_ty: ?[]const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (expected_ty) |ty| {
        if (errorEnumBranchValue(tokens, ty, tok.lexeme)) |value| {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{value});
            return true;
        }
        if (valueEnumBranchValue(ctx, tokens, ty, tok.lexeme)) |value| {
            try emitNumberConst(allocator, ctx, out, value, ty);
            return true;
        }
    }
    if (std.mem.eql(u8, tok.lexeme, "true")) {
        if (expected_ty) |ty| {
            if (!std.mem.eql(u8, ty, "bool")) return false;
        }
        try out.appendSlice(allocator, "    i32.const 1\n");
        return true;
    }
    if (std.mem.eql(u8, tok.lexeme, "false")) {
        if (expected_ty) |ty| {
            if (!std.mem.eql(u8, ty, "bool")) return false;
        }
        try out.appendSlice(allocator, "    i32.const 0\n");
        return true;
    }
    if (expected_ty) |ty| {
        if (findStructLocal(locals.struct_locals.items, tok.lexeme)) |struct_local| {
            const same_ty = std.mem.eql(u8, struct_local.ty, ty);
            const no_layout = findStructLayout(ctx.struct_layouts, ty) == null;
            if (same_ty and no_layout) {
                const decl = findStructDecl(ctx.structs, ty) orelse return false;
                try emitStructFieldsFromLocal(allocator, tokens, struct_local, decl, locals, ctx, false, out);
                return true;
            }
        }
        if (try emitUnionLocalPayloadForType(allocator, tok.lexeme, ty, locals, ctx, out)) return true;
    }
    if (findLocalName(locals.locals.items, tok.lexeme)) |local_name| {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        return true;
    }
    if (findCallbackCallArg(ctx.callback_call_args, tok.lexeme)) |callback_arg| {
        return try emitExpr(
            allocator,
            callback_arg.expr_tokens,
            callback_arg.expr_start,
            callback_arg.expr_end,
            locals,
            ctx,
            callback_arg.ty,
            out,
        );
    }
    if (localScalarConst(tokens, tok.lexeme)) |local_const| {
        const ty = expected_ty orelse local_const.ty;
        try emitNumberConst(allocator, ctx, out, local_const.value, ty);
        return true;
    }
    return false;
}

fn emitExprWithExpectedTy(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range: Range,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const ty = expected_ty orelse return false;
    if (try emitTupleExpr(allocator, tokens, range.start, range.end, locals, ctx, ty, out)) return true;
    if (try emitExpectedStorageAggLiteral(allocator, tokens, range, locals, ctx, ty, out)) return true;
    if (try emitStructLiteralExpr(allocator, tokens, range.start, range.end, locals, ctx, ty, out)) return true;
    return false;
}

fn emitExpectedStorageAggLiteral(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range: Range,
    locals: *const LocalSet,
    ctx: CodegenContext,
    ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const elem_ty = managedPayloadElemTypeFromName(ty) orelse return false;
    if (!isStorageAggLiteralExpr(tokens, range.start, range.end)) return false;
    if (!try emitStorageAggLiteral(allocator, tokens, range.start, range.end, STORAGE_OVERWRITE_TMP_LOCAL, elem_ty, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

/// Emit call arguments left-to-right; for n-ary fold ops, apply `op` after the 2nd+ arg.
/// When `require_arity` is non-null, require exactly that many args and always append one `op`.
fn emitCoreOpArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    arg_ty: []const u8,
    op: []const u8,
    require_arity: ?usize,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    var arg_start = args_start;
    var emitted_count: usize = 0;
    while (arg_start < args_end) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, arg_ty, out)) return false;
        if (require_arity == null and emitted_count > 0) {
            try appendFmt(allocator, out, "    {s}\n", .{op});
        }
        emitted_count += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (require_arity) |n| {
        if (emitted_count != n) return false;
        try appendFmt(allocator, out, "    {s}\n", .{op});
        return true;
    }
    return emitted_count != 0;
}

/// Mid-layer: entire `@name(...)` intrinsic dispatch (reflection / core ops / len-get-set / memory).
fn emitIntrinsicCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (try emitFieldReflectionIntrinsic(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, move_ctx, out)) {
        return true;
    }

    if (shouldEmitBoolSpecialCall(call_name, expected_ty, tokens, call_head.args_start, call_head.args_end, locals, ctx)) {
        return try emitBoolSpecialCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out);
    }

    if (std.mem.eql(u8, call_name, "as")) {
        if (try emitScalarAsCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out)) {
            return true;
        }
        return false;
    }

    if (std.mem.eql(u8, call_name, "is")) {
        return try emitUnionIsCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out);
    }

    if (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne")) {
        if (try emitUnionNilComparison(allocator, tokens, call_head.args_start, call_head.args_end, move_ctx, call_name, locals, ctx, out)) {
            return true;
        }
        if (try emitUnionPayloadComparisonLocal(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
            return true;
        }
        if (try emitUnionErrorBranchComparison(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
            return true;
        }
        if (try emitUnionPayloadComparisonCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
            return true;
        }
    }

    if (isNumericCoreFuncName(call_name)) {
        const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
        const op = numericWasmOp(call_name, op_ty) orelse return false;
        return try emitCoreOpArgs(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, op_ty, op, null, out);
    }

    if (isBitwiseCoreFuncName(call_name)) {
        const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
        if (!isCoreIntegerScalar(op_ty)) return false;
        const op = bitwiseWasmOp(call_name, op_ty) orelse return false;
        const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (!try emitExpr(allocator, tokens, call_head.args_start, first_end, locals, ctx, op_ty, out)) return false;
        if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return false;
        const second_start = first_end + 1;
        const second_end = findArgEnd(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return false;
        if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, op_ty, out)) return false;
        try appendFmt(allocator, out, "    {s}\n", .{op});
        return true;
    }

    if (isCountBitsCoreFuncName(call_name)) {
        const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
        if (!isCoreIntegerScalar(op_ty)) return false;
        const op = countBitsWasmOp(call_name, op_ty) orelse return false;
        const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return false;
        if (!try emitExpr(allocator, tokens, call_head.args_start, arg_end, locals, ctx, op_ty, out)) return false;
        try appendFmt(allocator, out, "    {s}\n", .{op});
        return true;
    }

    if (isNumericUnarySelectCoreFuncName(call_name)) {
        const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return false;
        return try emitNumericUnarySelectCall(allocator, tokens, call_head.args_start, arg_end, call_name, expected_ty, locals, ctx, out);
    }

    if (isNumericBinarySelectCoreFuncName(call_name)) {
        const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, first_end, locals, ctx) orelse "i32";
        return try emitNumericBinarySelectCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, op_ty, locals, ctx, out);
    }

    if (isFloatUnaryCoreFuncName(call_name)) {
        const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return false;
        const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, arg_end, locals, ctx) orelse return false;
        if (!isCoreFloatScalar(op_ty)) return false;
        const op = floatUnaryWasmOp(call_name, op_ty) orelse return false;
        if (!try emitExpr(allocator, tokens, call_head.args_start, arg_end, locals, ctx, op_ty, out)) return false;
        try appendFmt(allocator, out, "    {s}\n", .{op});
        return true;
    }

    if (isFloatBinaryCoreFuncName(call_name)) {
        const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, first_end, locals, ctx) orelse return false;
        if (!isCoreFloatScalar(op_ty)) return false;
        const op = floatBinaryWasmOp(call_name, op_ty) orelse return false;
        if (!try emitExpr(allocator, tokens, call_head.args_start, first_end, locals, ctx, op_ty, out)) return false;
        if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return false;
        const second_start = first_end + 1;
        const second_end = findArgEnd(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return false;
        if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, op_ty, out)) return false;
        try appendFmt(allocator, out, "    {s}\n", .{op});
        return true;
    }

    if (isComparisonCoreFuncName(call_name)) {
        if (try emitStorageContentComparisonCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
            return true;
        }

        const cmp_ty = inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
        const op_ty = codegenScalarType(ctx, cmp_ty);
        const op = comparisonWasmOp(call_name, op_ty) orelse return false;
        return try emitCoreOpArgs(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, cmp_ty, op, 2, out);
    }

    if (std.mem.eql(u8, call_name, "len")) {
        return try emitLenCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, out);
    }
    if (std.mem.eql(u8, call_name, "get")) {
        return try emitGetCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, move_ctx, out);
    }
    if (std.mem.eql(u8, call_name, "set")) {
        if (try emitStructSetExpr(allocator, tokens, call_head.args_start, call_head.args_end, expected_ty, locals, ctx, out)) {
            return true;
        }
        return try emitStorageSetExpr(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out);
    }
    if (std.mem.eql(u8, call_name, "put")) {
        return try emitStoragePutExpr(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out);
    }
    if (isMemoryLoadName(call_name)) {
        return try emitMemoryLoadCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out);
    }

    return false;
}

pub fn emitExprWithMoveContext(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: ?[]const u8, move_ctx: ?*const CallLastUseMoveContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (try emitExprWithExpectedTy(
        allocator,
        tokens,
        range,
        locals,
        ctx,
        expected_ty,
        out,
    )) return true;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .string) {
            const ty = expected_ty orelse return false;
            if (!std.mem.eql(u8, ty, "text") and storageElemTypeFromName(ty) == null) return false;
            const elem_ty = managedPayloadElemTypeFromName(ty) orelse return false;
            if (!std.mem.eql(u8, elem_ty, "u8")) return false;
            try emitStorageU8StringLiteralValue(allocator, tokens, range.start, ctx, out);
            return true;
        }
        if (tok.kind == .number) {
            try emitNumberConst(allocator, ctx, out, tok.lexeme, expected_ty orelse "i32");
            return true;
        }
        if (tokEq(tok, "nil")) {
            const ty = expected_ty orelse return false;
            if (!isErrorLikeType(tokens, ty)) return false;
            try out.appendSlice(allocator, "    i32.const 0\n");
            return true;
        }
        if (tok.kind == .ident) {
            if (try emitIdentLiteralOrLocal(
                allocator,
                tokens,
                tok,
                expected_ty,
                locals,
                ctx,
                out,
            )) return true;
        }
        if (tok.kind == .ident) {
            const imported_const = importedScalarConst(ctx, tokens, tok.lexeme) orelse return false;
            const ty = expected_ty orelse imported_const.ty;
            try emitNumberConst(allocator, ctx, out, imported_const.value, ty);
            return true;
        }
        return false;
    }

    const call_head = exprCallHead(tokens, range) orelse return false;
    const call_name = tokens[call_head.name_idx].lexeme;

    if (call_head.is_intrinsic) {
        return try emitIntrinsicCall(
            allocator,
            tokens,
            call_head,
            call_name,
            locals,
            ctx,
            expected_ty,
            move_ctx,
            out,
        );
    }

    if (isCoreWasmCallName(call_name)) return false;

    if (findCallbackBinding(ctx.callback_bindings, call_name)) |binding| {
        return try emitCallbackBindingCall(allocator, tokens, call_head, locals, ctx, binding, out);
    }

    if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| {
        return try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out);
    }

    if (findWasiHostImportForTokens(ctx, tokens, call_name)) |wasi_import| {
        return try emitWasiHostImportExpr(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, false, out, gen_hooks.emitExpr);
    }

    const host_import = findHostImportForTokens(ctx.host_imports, tokens, call_name) orelse return false;
    var arg_start = call_head.args_start;
    var param_idx: usize = 0;
    while (arg_start < call_head.args_end) {
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        if (stringLiteralArgLexeme(tokens, arg_start, arg_end)) |lexeme| {
            if (!hostParamIsPtrLen(host_import, param_idx)) return error.NoMatchingCall;
            const data = ctx.string_data.find(lexeme) orelse return error.NoMatchingCall;
            try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
            try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
            param_idx += 2;
        } else if (try emitStoragePtrLenHostArg(allocator, tokens, arg_start, arg_end, locals, host_import, param_idx, out)) {
            param_idx += 2;
        } else {
            const param_ty = if (param_idx < host_import.params.len) host_import.params[param_idx] else null;
            if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out)) {
                return false;
            }
            param_idx += 1;
        }
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx != host_import.params.len) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    call ${s}\n", .{host_import.alias});
    return true;
}

pub fn emitNumericUnarySelectCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, arg_start: usize, arg_end: usize, call_name: []const u8, expected_ty: ?[]const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!std.mem.eql(u8, call_name, "abs")) return false;
    const source_ty = inferExprType(tokens, arg_start, arg_end, locals, ctx) orelse absSourceTypeFromResult(expected_ty) orelse "i32";
    const result_ty = absResultType(source_ty) orelse return false;
    if (expected_ty) |expected| {
        if (!std.mem.eql(u8, result_ty, expected)) return false;
    }
    if (isCoreFloatScalar(source_ty)) {
        const op = floatUnaryWasmOp(call_name, source_ty) orelse return false;
        if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, source_ty, out)) return false;
        try appendFmt(allocator, out, "    {s}\n", .{op});
        return true;
    }
    if (!isCoreIntegerScalar(source_ty) or isUnsignedScalar(source_ty)) return false;

    const tmp = numericSelectLeftTmp(source_ty);
    const wt = wasmType(source_ty);
    const cmp = comparisonWasmOp("lt", source_ty) orelse return false;
    try appendFmt(allocator, out, "    {s}.const 0\n", .{wt});
    if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, source_ty, out)) return false;
    try appendFmt(allocator, out, "    local.tee ${s}\n", .{tmp});
    try appendFmt(allocator, out, "    {s}.sub\n", .{wt});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tmp});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tmp});
    try appendFmt(allocator, out, "    {s}.const 0\n", .{wt});
    try appendFmt(allocator, out, "    {s}\n", .{cmp});
    try out.appendSlice(allocator, "    select\n");
    return true;
}

pub fn emitNumericBinarySelectCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, call_name: []const u8, op_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;

    if (isCoreFloatScalar(op_ty)) {
        const op = floatBinaryWasmOp(call_name, op_ty) orelse return false;
        if (!try emitExpr(allocator, tokens, args_start, first_end, locals, ctx, op_ty, out)) return false;
        var arg_start = first_end + 1;
        var emitted_count: usize = 1;
        while (arg_start < args_end) {
            const arg_end = findArgEnd(tokens, arg_start, args_end);
            if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, op_ty, out)) return false;
            try appendFmt(allocator, out, "    {s}\n", .{op});
            emitted_count += 1;
            arg_start = arg_end;
            if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (emitted_count < 2) return false;
        return true;
    }
    if (!isCoreIntegerScalar(op_ty)) return false;

    const temps = numericSelectTemps(op_ty);
    const cmp_name = if (std.mem.eql(u8, call_name, "min")) "lt" else if (std.mem.eql(u8, call_name, "max")) "gt" else return false;
    const cmp = comparisonWasmOp(cmp_name, op_ty) orelse return false;
    if (!try emitExpr(allocator, tokens, args_start, first_end, locals, ctx, op_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{temps.left});
    var arg_start = first_end + 1;
    var emitted_count: usize = 1;
    while (arg_start < args_end) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, op_ty, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{temps.right});
        try appendNumericSelectFromTemps(allocator, out, temps, cmp);
        emitted_count += 1;
        arg_start = arg_end;
        if (arg_start < args_end) {
            if (!tokEq(tokens[arg_start], ",")) return false;
            arg_start += 1;
            if (arg_start < args_end) {
                try appendFmt(allocator, out, "    local.set ${s}\n", .{temps.left});
            }
        }
    }
    if (emitted_count < 2) return false;
    return true;
}

pub fn appendNumericSelectFromTemps(allocator: std.mem.Allocator, out: *std.ArrayList(u8), temps: NumericSelectTemps, cmp: []const u8) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.left});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.right});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.left});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.right});
    try appendFmt(allocator, out, "    {s}\n", .{cmp});
    try out.appendSlice(allocator, "    select\n");
}

pub fn emitBareUserFuncCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    return emitBareUserFuncCallWithMoveContext(allocator, tokens, start_idx, end_idx, end_idx, true, locals, null, ctx, out);
}

pub fn emitBareUserFuncCallWithMoveContext(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != 0) return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    return true;
}

pub fn emitBoolSpecialCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (std.mem.eql(u8, name, "not")) {
        const arg_end = findArgEnd(tokens, args_start, args_end);
        if (arg_end != args_end) return false;
        if (!try emitExpr(allocator, tokens, args_start, arg_end, locals, ctx, "bool", out)) return false;
        try out.appendSlice(allocator, "    i32.eqz\n");
        return true;
    }

    if (std.mem.eql(u8, name, "and")) {
        return try emitShortCircuitAnd(allocator, tokens, args_start, args_end, locals, ctx, out);
    }
    if (std.mem.eql(u8, name, "or")) {
        return try emitShortCircuitOr(allocator, tokens, args_start, args_end, locals, ctx, out);
    }
    return false;
}

pub fn shouldEmitBoolSpecialCall(name: []const u8, expected_ty: ?[]const u8, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    if (!isBoolSpecialFuncName(name)) return false;
    if (std.mem.eql(u8, name, "not")) return true;
    if (expected_ty) |ty| {
        if (!std.mem.eql(u8, ty, "bool")) return false;
        return shouldInferBoolSpecialCall(name, tokens, args_start, args_end, locals, ctx);
    }
    return shouldInferBoolSpecialCall(name, tokens, args_start, args_end, locals, ctx);
}

pub fn emitShortCircuitAnd(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx >= end_idx) return false;

    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (!try emitExpr(allocator, tokens, start_idx, first_end, locals, ctx, "bool", out)) return false;
    if (first_end == end_idx) return true;
    if (!tokEq(tokens[first_end], ",")) return false;

    try out.appendSlice(allocator, "    if (result i32)\n");
    if (!try emitShortCircuitAnd(allocator, tokens, first_end + 1, end_idx, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    else\n");
    try out.appendSlice(allocator, "    i32.const 0\n");
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn emitShortCircuitOr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx >= end_idx) return false;

    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (!try emitExpr(allocator, tokens, start_idx, first_end, locals, ctx, "bool", out)) return false;
    if (first_end == end_idx) return true;
    if (!tokEq(tokens[first_end], ",")) return false;

    try out.appendSlice(allocator, "    if (result i32)\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    else\n");
    if (!try emitShortCircuitOr(allocator, tokens, first_end + 1, end_idx, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn appendFuncParamStructFields(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    ctx: CodegenContext,
    locals: *LocalSet,
    param_name: []const u8,
    abi_ty: []const u8,
    decl: StructDecl,
) !void {
    if (findStructLayout(ctx.struct_layouts, abi_ty) != null) {
        try locals.appendBorrowedLocalWithOrigin(allocator, param_name, abi_ty, false, .param_or_import);
        for (decl.fields) |field| {
            const field_ty = try substituteStructFieldType(allocator, decl, abi_ty, field.ty, &locals.owned_names);
            try appendManagedStructFieldMetaLocal(allocator, locals, param_name, field.name, field_ty);
        }
        return;
    }
    for (decl.fields) |field| {
        const field_ty = try substituteStructFieldType(allocator, decl, abi_ty, field.ty, &locals.owned_names);
        try appendBorrowedLocalField(allocator, locals, func.tokens, ctx, param_name, field.name, field_ty);
    }
}

pub fn appendFuncParamLocals(allocator: std.mem.Allocator, func: FuncDecl, ctx: CodegenContext, locals: *LocalSet) !void {
    for (func.params) |param| {
        if (param.callback != null) continue;
        const raw_abi_ty = funcParamAbiType(param);
        const abi_ty = try substituteGenericTypeOwned(allocator, raw_abi_ty, ctx.type_bindings, &locals.owned_names);
        if (try parse_type_union_layout_from_name(allocator, func.tokens, abi_ty, ctx.structs, ctx.struct_layouts, &locals.owned_names)) |layout| {
            errdefer freeUnionLayout(allocator, layout);
            try locals.appendUnionLocalWithOrigin(allocator, param.name, layout, false, true, .param_or_import);
        } else if (findPayloadEnumDecl(ctx.payload_enums, abi_ty)) |decl| {
            const layout = try buildPayloadEnumUnionLayout(allocator, decl, func.tokens, ctx.structs, ctx.struct_layouts, &locals.owned_names);
            errdefer freeUnionLayout(allocator, layout);
            try locals.appendUnionLocalWithOrigin(allocator, param.name, layout, false, true, .param_or_import);
        } else if (managedPayloadElemTypeFromName(abi_ty)) |elem_ty| {
            try locals.appendBorrowedLocalWithOrigin(allocator, param.name, abi_ty, false, .param_or_import);
            try locals.storage_locals.append(allocator, .{ .name = param.name, .ty = abi_ty, .elem_ty = elem_ty });
        } else if (findStructDecl(ctx.structs, abi_ty)) |decl| {
            try locals.struct_locals.append(allocator, .{ .name = param.name, .ty = abi_ty, .origin = .param_or_import });
            try appendFuncParamStructFields(allocator, func, ctx, locals, param.name, abi_ty, decl);
        } else if (isTupleTypeName(abi_ty)) {
            try locals.struct_locals.append(allocator, .{ .name = param.name, .ty = abi_ty, .origin = .param_or_import });
            const arity = tupleArity(abi_ty) orelse return error.UnsupportedLowering;
            var elem_idx: usize = 0;
            while (elem_idx < arity) : (elem_idx += 1) {
                const elem_ty = tupleElementTypeAt(abi_ty, elem_idx) orelse return error.UnsupportedLowering;
                var field_buf: [32]u8 = undefined;
                const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{elem_idx});
                try appendBorrowedLocalField(allocator, locals, func.tokens, ctx, param.name, field_name, elem_ty);
            }
        } else {
            try locals.appendBorrowedLocalWithOrigin(allocator, param.name, abi_ty, false, .param_or_import);
        }
    }
}

pub fn funcHasCallbackParams(func: FuncDecl) bool {
    for (func.params) |param| {
        if (param.callback != null) return true;
    }
    return false;
}

pub fn emitLenCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, out: *std.ArrayList(u8)) !bool {
    const arg_end = findArgEnd(tokens, start_idx, end_idx);
    if (arg_end != start_idx + 1 or arg_end != end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage_name = findStorageReadableLocalName(tokens, locals, tokens[start_idx].lexeme) orelse return false;
    try emitStorageLenPtr(allocator, out, storage_name);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

fn emitTupleStructLocalGet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    second_start: usize,
    second_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const struct_local = findStructLocal(locals.struct_locals.items, name) orelse return false;
    if (!isTupleTypeName(struct_local.ty)) return false;
    const elem_info = tupleGetElementInfo(tokens, second_start, second_end, struct_local.ty) orelse return false;

    if (isTupleTypeName(elem_info.ty)) {
        const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ struct_local.name, elem_info.index });
        defer allocator.free(nested_base);
        try emitTupleLocalGet(allocator, nested_base, elem_info.ty, ctx, out);
        return true;
    }

    if (findStructDecl(ctx.structs, elem_info.ty)) |decl| {
        if (findStructLayout(ctx.struct_layouts, elem_info.ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
            const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ struct_local.name, elem_info.index });
            defer allocator.free(nested_base);
            try emitPureScalarStructLocalGet(allocator, nested_base, decl, out);
            return true;
        }
    }

    try appendFmt(allocator, out, "    local.get ${s}.{d}\n", .{ struct_local.name, elem_info.index });
    if (isManagedLocalType(elem_info.ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}

pub fn emitGetCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, move_ctx: ?*const CallLastUseMoveContext, out: *std.ArrayList(u8)) !bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (try emitTupleFieldPathGetCall(allocator, tokens, start_idx, end_idx, first_end, locals, ctx, out)) {
        return true;
    }
    if (second_end != end_idx) {
        return try emitPathGetCall(allocator, tokens, start_idx, end_idx, first_end, locals, ctx, out);
    }

    if (try emitManagedStructExprFieldGet(allocator, tokens, start_idx, first_end, second_start, second_end, locals, ctx, out)) {
        return true;
    }

    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) {
        const storage_ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return false;
        const elem_ty = storageElemTypeFromName(storage_ty) orelse return false;
        const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
        if (!try emitExpr(allocator, tokens, start_idx, first_end, locals, ctx, storage_ty, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try emitStorageBoundsCheck(allocator, tokens, second_start, second_end, locals, ctx, STORAGE_PUT_SOURCE_TMP_LOCAL, 1, out);
        if (isTupleTypeName(elem_ty)) {
            try emitStorageDataPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
            if (elem_bytes != 1) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
                try out.appendSlice(allocator, "    i32.mul\n");
            }
            try out.appendSlice(allocator, "    i32.add\n");
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        } else {
            try emitStorageDataPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
            if (elem_bytes != 1) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
                try out.appendSlice(allocator, "    i32.mul\n");
            }
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, elem_ty);
            if (isManagedLocalType(elem_ty, ctx)) {
                try out.appendSlice(allocator, "    ;; storage-managed-get-inc\n");
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
        }
        return true;
    }

    const name = tokens[start_idx].lexeme;

    if (try emitUnionStoragePayloadGetCall(allocator, tokens, name, second_start, second_end, locals, ctx, out)) {
        return true;
    }

    if (findStoragePrimitiveLocal(locals.storage_locals.items, name)) |storage| {
        const elem_bytes = storageElementByteWidthForType(storage.elem_ty, ctx) orelse return false;
        try emitStorageBoundsCheck(allocator, tokens, second_start, second_end, locals, ctx, name, 1, out);
        if (isTupleTypeName(storage.elem_ty)) {
            try emitStorageDataPtr(allocator, out, name);
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
            if (elem_bytes != 1) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
                try out.appendSlice(allocator, "    i32.mul\n");
            }
            try out.appendSlice(allocator, "    i32.add\n");
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, storage.elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        } else {
            try emitStorageDataPtr(allocator, out, name);
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
            if (elem_bytes != 1) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
                try out.appendSlice(allocator, "    i32.mul\n");
            }
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, storage.elem_ty);
            if (isManagedLocalType(storage.elem_ty, ctx)) {
                try out.appendSlice(allocator, "    ;; storage-managed-get-inc\n");
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
        }
        return true;
    }

    if (try emitTupleStructLocalGet(
        allocator,
        tokens,
        name,
        second_start,
        second_end,
        locals,
        ctx,
        out,
    )) return true;

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (second_end != second_start + 1 or !isDotIdent(tokens[second_start].lexeme)) return false;
        const field_name = publicDeclName(tokens[second_start].lexeme);
        if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
            const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
            const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
                findStructFieldType(decl, field_name) orelse return false;
            const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
            const move_source = if (move_ctx) |ctx_info|
                try fieldGetLastUseMoveSource(allocator, tokens, start_idx, end_idx, struct_local, field_ty, ctx_info.*, locals, ctx)
            else
                null;
            try appendFmt(allocator, out, "    local.get ${s}\n", .{struct_local.name});
            try out.appendSlice(allocator, "    call $__arc_payload\n");
            try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, field_ty);
            if (isManagedStructField(layout, field_name) and move_source == null) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            if (move_source) |source| {
                try appendFmt(allocator, out, "    ;; field-get-move {s}.{s}\n", .{ source.source_name, field_name });
                try emitZeroValueForType(allocator, ctx, out, field_ty);
                try appendManagedStructFieldPtr(allocator, out, struct_local.name, field_offset);
                try appendStoreForPayloadType(allocator, out, field_ty);
            }
            return true;
        }
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
        const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
            findStructFieldType(decl, field_name) orelse return false;
        if (try emitUnmanagedStructFieldGet(allocator, tokens, struct_local, field_name, field_ty, locals, ctx, out)) {
            return true;
        }
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{ struct_local.name, field_name });
        return true;
    }

    if (try emitUnionStructFieldGetCall(allocator, tokens, name, tokens[second_start], second_end == second_start + 1, locals, ctx, out)) {
        return true;
    }

    return false;
}

pub fn emitPathGetCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, first_end: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    var current = PathGetValue{
        .expr_start = start_idx,
        .expr_end = first_end,
        .ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return false,
        .local_name = null,
        .owned = false,
    };

    var segment_start = first_end + 1;
    while (segment_start < end_idx) {
        const segment_end = findArgEnd(tokens, segment_start, end_idx);
        if (segment_end == segment_start) return false;
        const has_more = segment_end < end_idx;
        if (has_more and !tokEq(tokens[segment_end], ",")) return false;

        const next_ty = if (try emitPathGetSegment(
            allocator,
            tokens,
            &current,
            segment_start,
            segment_end,
            has_more,
            locals,
            ctx,
            &owned_types,
            out,
        )) |ty| ty else return false;

        // Tuple path intermediate keeps packed base in $__tuple_pack_base_tmp (raw pointer, not managed).
        const next_local: ?[]const u8 = if (!has_more)
            null
        else if (isTupleTypeName(next_ty))
            TUPLE_PACK_BASE_TMP_LOCAL
        else
            STORAGE_OVERWRITE_TMP_LOCAL;
        current = .{
            .expr_start = 0,
            .expr_end = 0,
            .ty = next_ty,
            .local_name = next_local,
            .owned = has_more and next_local != null and
                std.mem.eql(u8, next_local.?, STORAGE_OVERWRITE_TMP_LOCAL) and
                isManagedLocalType(next_ty, ctx),
        };

        if (!has_more) return true;
        segment_start = segment_end + 1;
    }

    return false;
}

const PathGetValue = struct {
    expr_start: usize,
    expr_end: usize,
    ty: []const u8,
    local_name: ?[]const u8,
    owned: bool,
};

pub fn emitPathGetSegment(allocator: std.mem.Allocator, tokens: []const lexer.Token, current: *PathGetValue, segment_start: usize, segment_end: usize, has_more: bool, locals: *const LocalSet, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) CodegenError!?[]const u8 {
    if (segment_end == segment_start + 1 and isDotIdent(tokens[segment_start].lexeme)) {
        return try emitPathGetFieldSegment(
            allocator,
            tokens,
            current,
            tokens[segment_start].lexeme,
            has_more,
            locals,
            ctx,
            owned_types,
            out,
        );
    }

    return try emitPathGetIndexSegment(
        allocator,
        tokens,
        current,
        segment_start,
        segment_end,
        has_more,
        locals,
        ctx,
        out,
    );
}

pub fn emitPathGetIndexSegment(allocator: std.mem.Allocator, tokens: []const lexer.Token, current: *PathGetValue, index_start: usize, index_end: usize, has_more: bool, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!?[]const u8 {
    // Intermediate Tuple from prior path segment: index into packed leaves at base tmp.
    if (isTupleTypeName(current.ty) and current.local_name != null and
        std.mem.eql(u8, current.local_name.?, TUPLE_PACK_BASE_TMP_LOCAL))
    {
        const elem_info = tupleGetElementInfo(tokens, index_start, index_end, current.ty) orelse return null;
        if (has_more and isTupleTypeName(elem_info.ty)) {
            // Nested Tuple: advance base to sub-element start; keep pointer intermediate.
            const elem_offset = tupleElementPackOffsetWithStructs(current.ty, elem_info.index, ctx.structs) orelse return error.UnsupportedLowering;
            if (elem_offset != 0) {
                try appendFmt(allocator, out, "    local.get ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_offset});
                try out.appendSlice(allocator, "    i32.add\n");
                try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            }
            return elem_info.ty;
        }
        // Nested pure-scalar struct slot: advance base for further field path segments.
        if (has_more and findStructDecl(ctx.structs, elem_info.ty) != null and
            findStructLayout(ctx.struct_layouts, elem_info.ty) == null and
            pureScalarStructPackWidth(findStructDecl(ctx.structs, elem_info.ty).?, ctx.structs) != null)
        {
            const elem_offset = tupleElementPackOffsetWithStructs(current.ty, elem_info.index, ctx.structs) orelse return error.UnsupportedLowering;
            if (elem_offset != 0) {
                try appendFmt(allocator, out, "    local.get ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_offset});
                try out.appendSlice(allocator, "    i32.add\n");
                try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            }
            return elem_info.ty;
        }
        try appendLoadTupleElementOwningFromPackedBase(
            allocator,
            out,
            current.ty,
            elem_info.index,
            TUPLE_PACK_BASE_TMP_LOCAL,
            "    ",
            ctx,
        );
        if (has_more) {
            if (isTupleTypeName(elem_info.ty)) return error.UnsupportedLowering;
            try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
        }
        return elem_info.ty;
    }

    const elem_ty = storageElemTypeFromName(current.ty) orelse return null;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return null;
    const storage_name = try ensurePathGetCurrentLocal(allocator, tokens, current, locals, ctx, out);

    try emitStorageBoundsCheck(allocator, tokens, index_start, index_end, locals, ctx, storage_name, 1, out);
    if (isTupleTypeName(elem_ty)) {
        try emitStorageDataPtr(allocator, out, storage_name);
        if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return error.NoMatchingCall;
        if (elem_bytes != 1) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try releasePathGetCurrentIfOwned(allocator, current.*, ctx, out);
        if (has_more) {
            // Keep packed element base for @get(storage, i, j) chaining.
            return elem_ty;
        }
        try appendLoadTupleLeavesOwningToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        return elem_ty;
    }
    try emitStorageDataPtr(allocator, out, storage_name);
    if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return error.NoMatchingCall;
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "    i32.mul\n");
    }
    try out.appendSlice(allocator, "    i32.add\n");
    try appendLoadForPayloadType(allocator, out, elem_ty);
    if (isManagedLocalType(elem_ty, ctx)) {
        try out.appendSlice(allocator, "    ;; path-storage-managed-get-inc\n");
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try releasePathGetCurrentIfOwned(allocator, current.*, ctx, out);
    if (has_more) {
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    }
    return elem_ty;
}

pub fn emitPathGetFieldSegment(allocator: std.mem.Allocator, tokens: []const lexer.Token, current: *PathGetValue, dot_field: []const u8, has_more: bool, locals: *const LocalSet, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) CodegenError!?[]const u8 {
    const layout = findStructLayout(ctx.struct_layouts, current.ty) orelse return null;
    const decl = findStructDecl(ctx.structs, current.ty) orelse return null;
    const field_name = publicDeclName(dot_field);
    const field = findStructField(decl, field_name) orelse return null;
    const field_ty = try substituteStructFieldType(allocator, decl, current.ty, field.ty, owned_types);
    const field_offset = structFieldPayloadOffset(decl, field_name) orelse return null;
    const struct_name = try ensurePathGetCurrentLocal(allocator, tokens, current, locals, ctx, out);

    try appendManagedStructFieldPtr(allocator, out, struct_name, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    if (isManagedStructField(layout, field_name)) {
        try out.appendSlice(allocator, "    ;; path-field-managed-get-inc\n");
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try releasePathGetCurrentIfOwned(allocator, current.*, ctx, out);
    if (has_more) {
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    }
    return field_ty;
}

pub fn ensurePathGetCurrentLocal(allocator: std.mem.Allocator, tokens: []const lexer.Token, current: *PathGetValue, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError![]const u8 {
    if (current.local_name) |name| return name;
    if (!try emitExpr(allocator, tokens, current.expr_start, current.expr_end, locals, ctx, current.ty, out)) {
        return error.NoMatchingCall;
    }
    current.owned = isManagedLocalType(current.ty, ctx) and !isDirectManagedLocalExpr(tokens, current.expr_start, current.expr_end, locals, ctx);
    current.local_name = STORAGE_OVERWRITE_TMP_LOCAL;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return STORAGE_OVERWRITE_TMP_LOCAL;
}

pub fn releasePathGetCurrentIfOwned(allocator: std.mem.Allocator, current: PathGetValue, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    if (!current.owned or !isManagedLocalType(current.ty, ctx)) return;
    const local_name = current.local_name orelse return;
    try appendFmt(allocator, out, "    ;; path-get-release {s}\n", .{local_name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
}

pub fn emitMemoryLoadCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (second_end != end_idx) return false;

    const op = memoryLoadWasmOp(call_name) orelse return false;
    const width = memoryLoadByteWidth(call_name) orelse return false;
    try emitStorageBoundsCheck(allocator, tokens, second_start, second_end, locals, ctx, tokens[start_idx].lexeme, width, out);
    try emitStorageDataPtr(allocator, out, tokens[start_idx].lexeme);
    if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
    try out.appendSlice(allocator, "    i32.add\n");
    try appendFmt(allocator, out, "    {s}\n", .{op});
    return true;
}

pub fn emitScalarAsCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    const target_end = findArgEnd(tokens, args_start, args_end);
    if (target_end == args_start or target_end >= args_end or !tokEq(tokens[target_end], ",")) return false;
    const target_ty = scalarAsTargetType(tokens, args_start, target_end) orelse return false;

    const source_start = target_end + 1;
    const source_end = trimTrailingComma(tokens, source_start, args_end);
    if (source_start >= source_end) return false;

    const source_ty = inferExprType(tokens, source_start, source_end, locals, ctx) orelse target_ty;
    if (!isCoreWasmScalar(source_ty)) return false;
    if (!try emitExpr(allocator, tokens, source_start, source_end, locals, ctx, source_ty, out)) return false;
    if (scalarConvertWasmOp(source_ty, target_ty)) |op| {
        try appendFmt(allocator, out, "    {s}\n", .{op});
    }
    return true;
}

pub fn appendCallbackArgAliasLocals(allocator: std.mem.Allocator, parent: *const LocalSet, locals: *LocalSet, arg: CallbackCallArg) !void {
    const actual = arg.actual_name orelse return;
    if (findLocalType(parent.locals.items, actual)) |ty| {
        const actual_name = findLocalName(parent.locals.items, actual) orelse actual;
        try locals.locals.append(allocator, .{
            .name = actual_name,
            .source_name = arg.source_name,
            .ty = ty,
            .origin = findLocalOrigin(parent.locals.items, actual) orelse .unknown,
            .emit_decl = false,
        });
    }
    if (findStructLocal(parent.struct_locals.items, actual)) |struct_local| {
        try locals.struct_locals.append(allocator, .{
            .name = struct_local.name,
            .source_name = arg.source_name,
            .ty = struct_local.ty,
            .origin = struct_local.origin,
        });
    }
    if (findStorageLocal(parent.storage_locals.items, actual)) |storage_local| {
        try locals.storage_locals.append(allocator, .{
            .name = storage_local.name,
            .source_name = arg.source_name,
            .ty = storage_local.ty,
            .elem_ty = storage_local.elem_ty,
        });
    }
    if (findUnionLocal(parent.union_locals.items, actual)) |union_local| {
        try locals.union_locals.append(allocator, .{
            .name = union_local.name,
            .source_name = arg.source_name,
            .layout = union_local.layout,
            .owns_layout = false,
        });
    }
}

pub fn emitCallbackBindingLambdaCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, binding: CallbackBinding, out: *std.ArrayList(u8)) CodegenError!bool {
    if (binding.lambda_params.len != binding.shape.param_types.len) return false;
    const callback_args = try collect_callback_call_args(allocator, tokens, call_head, locals, ctx, binding);
    defer allocator.free(callback_args);

    var lambda_locals = try cloneLocalSet(allocator, locals);
    defer lambda_locals.deinit(allocator);
    for (callback_args) |arg| {
        try appendCallbackArgAliasLocals(allocator, locals, &lambda_locals, arg);
    }

    var lambda_ctx = ctx;
    lambda_ctx.callback_call_args = callback_args;
    if (!lambdaShapeIsBlock(binding)) {
        return try emitExpr(
            allocator,
            binding.arg_tokens,
            binding.body_start,
            binding.body_end,
            &lambda_locals,
            lambda_ctx,
            binding.shape.return_type,
            out,
        );
    }

    try collect_body_locals(allocator, binding.arg_tokens, binding.body_start, binding.body_end, lambda_ctx, &lambda_locals);
    if (binding.shape.return_type) |ret_ty| {
        try appendFmt(allocator, out, "    block $__lambda_ret (result {s})\n", .{codegenWasmType(lambda_ctx, ret_ty)});
    } else {
        try out.appendSlice(allocator, "    block $__lambda_ret\n");
    }
    const lambda_defer = DeferContext{
        .parent = null,
        .start_idx = binding.body_start,
        .end_idx = binding.body_end,
        .registered_end_idx = binding.body_end,
    };
    const lambda_results: []const []const u8 = if (binding.shape.return_type) |ret_ty|
        &[_][]const u8{ret_ty}
    else
        &.{};
    try gen_hooks.emitBody(
        allocator,
        binding.arg_tokens,
        binding.body_start,
        binding.body_end,
        binding.body_start,
        &lambda_locals,
        &lambda_locals,
        &EMPTY_LOCAL_SET,
        lambda_ctx,
        lambda_results,
        NO_RESULT_ITEMS,
        null,
        null,
        null,
        &lambda_defer,
        "__lambda_ret",
        null,
        out,
    );
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn lambdaShapeIsBlock(binding: CallbackBinding) bool {
    return binding.body_start > 0 and binding.body_end > binding.body_start and tokEq(binding.arg_tokens[binding.body_start - 1], "{");
}

pub fn emitCallbackBindingFuncRefCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, binding: CallbackBinding, out: *std.ArrayList(u8)) CodegenError!bool {
    const func_name = binding.func_name orelse return false;
    const target = findCallbackRefFunc(binding.arg_tokens, ctx, func_name, binding.shape) orelse return false;
    return try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, target, out);
}

pub fn emitCallbackBindingCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, binding: CallbackBinding, out: *std.ArrayList(u8)) CodegenError!bool {
    return switch (binding.kind) {
        .lambda => try emitCallbackBindingLambdaCall(allocator, tokens, call_head, locals, ctx, binding, out),
        .func_ref => try emitCallbackBindingFuncRefCall(allocator, tokens, call_head, locals, ctx, binding, out),
    };
}

pub fn emitUserFuncCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, func: FuncDecl, out: *std.ArrayList(u8)) !bool {
    return emitUserFuncCallWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, func, null, out);
}

pub fn emitUserFuncCallWithMoveContext(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, func: FuncDecl, move_ctx: ?*const CallLastUseMoveContext, out: *std.ArrayList(u8)) !bool {
    const variadic_idx = func_variadic_param_index(func);
    var move_sources = std.ArrayList(LastUseManagedMoveSource).empty;
    defer move_sources.deinit(allocator);
    var arg_start = start_idx;
    var param_idx: usize = 0;
    while (arg_start < end_idx and (variadic_idx == null or param_idx < variadic_idx.?)) {
        if (param_idx >= func.params.len) return false;
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        const param = func.params[param_idx];
        if (param.callback) |callback| {
            if (!callArgMatchesCallbackShape(tokens, arg_start, arg_end, locals, ctx, callback.shape)) return false;
        } else {
            const param_ty = param.ty;
            const move_source = if (move_ctx) |ctx_info|
                directManagedCallLastUseMoveSource(tokens, arg_start, arg_end, ctx_info.*, locals, ctx)
            else
                null;
            const param_is_union = findTopLevelTypeSeparator(param_ty, '|') != null;
            if (!try emitUserFuncArg(allocator, tokens, arg_start, arg_end, param_ty, move_source == null, locals, ctx, out)) return false;
            if (!param_is_union and move_source == null and isDirectManagedLocalExpr(tokens, arg_start, arg_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            } else if (move_source) |source| {
                if (!hasMoveSource(move_sources.items, source.actual_name)) try move_sources.append(allocator, source);
            }
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < end_idx and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }

    if (variadic_idx) |rest_idx| {
        if (rest_idx >= func.params.len) return false;
        if (!try emitVariadicPackArg(allocator, tokens, arg_start, end_idx, funcVariadicElemType(func.params[rest_idx]), locals, ctx, out)) return false;
        param_idx = func.params.len;
    } else if (param_idx != func.params.len) {
        return false;
    }
    try appendFmt(allocator, out, "    call ${s}\n", .{func.name});
    for (move_sources.items) |source| {
        try appendFmt(allocator, out, "    ;; arc-call-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

pub fn emitUserFuncCallWithUnionBindingMove(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, stmt_end: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, func: FuncDecl, out: *std.ArrayList(u8)) !bool {
    const variadic_idx = func_variadic_param_index(func);
    var move_sources = std.ArrayList(LastUseManagedMoveSource).empty;
    defer move_sources.deinit(allocator);
    var arg_start = start_idx;
    var param_idx: usize = 0;
    while (arg_start < end_idx and (variadic_idx == null or param_idx < variadic_idx.?)) {
        if (param_idx >= func.params.len) return false;
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        const param = func.params[param_idx];
        if (param.callback) |callback| {
            if (!callArgMatchesCallbackShape(tokens, arg_start, arg_end, locals, ctx, callback.shape)) return false;
        } else {
            const param_ty = param.ty;
            const move_source = directManagedUnionBindingCallMoveSource(
                tokens,
                arg_start,
                arg_end,
                end_idx,
                stmt_end,
                body_end,
                allow_last_use_move,
                locals,
                ctx,
                defer_ctx,
            );
            const param_is_union = findTopLevelTypeSeparator(param_ty, '|') != null;
            if (!try emitUserFuncArg(allocator, tokens, arg_start, arg_end, param_ty, move_source == null, locals, ctx, out)) return false;
            if (!param_is_union and move_source == null and isDirectManagedLocalExpr(tokens, arg_start, arg_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            } else if (move_source) |source| {
                if (!hasMoveSource(move_sources.items, source.actual_name)) try move_sources.append(allocator, source);
            }
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < end_idx and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }

    if (variadic_idx) |rest_idx| {
        if (rest_idx >= func.params.len) return false;
        if (!try emitVariadicPackArg(allocator, tokens, arg_start, end_idx, funcVariadicElemType(func.params[rest_idx]), locals, ctx, out)) return false;
        param_idx = func.params.len;
    } else if (param_idx != func.params.len) {
        return false;
    }
    try appendFmt(allocator, out, "    call ${s}\n", .{func.name});
    for (move_sources.items) |source| {
        try appendFmt(allocator, out, "    ;; arc-call-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

pub fn emitVariadicPackArg(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, elem_ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx < end_idx and tokEq(tokens[start_idx], "...")) {
        const spread_start = start_idx + 1;
        if (findArgEnd(tokens, spread_start, end_idx) != end_idx) return false;
        if (spread_start + 1 != end_idx or tokens[spread_start].kind != .ident) return false;
        const rest = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[spread_start].lexeme) orelse return false;
        if (!std.mem.eql(u8, rest.elem_ty, elem_ty)) return false;
        try appendFmt(allocator, out, "    local.get ${s}\n", .{tokens[spread_start].lexeme});
        return true;
    }

    try emitEmptyStorageForElemType(allocator, elem_ty, ctx, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{VARIADIC_PACK_TMP_LOCAL});

    var arg_start = start_idx;
    while (arg_start < end_idx) {
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        if (arg_end == arg_start) return false;
        if (!try emitStoragePutOneCall(allocator, tokens, arg_start, arg_end, VARIADIC_PACK_TMP_LOCAL, VARIADIC_PACK_TMP_LOCAL, elem_ty, locals, ctx, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{VARIADIC_PACK_TMP_LOCAL});
        arg_start = arg_end;
        if (arg_start < end_idx and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }

    try appendFmt(allocator, out, "    local.get ${s}\n", .{VARIADIC_PACK_TMP_LOCAL});
    return true;
}

pub fn absSourceTypeFromResult(result_ty: ?[]const u8) ?[]const u8 {
    const ty = result_ty orelse return null;
    if (std.mem.eql(u8, ty, "u8")) return "i8";
    if (std.mem.eql(u8, ty, "u16")) return "i16";
    if (std.mem.eql(u8, ty, "u32")) return "i32";
    if (std.mem.eql(u8, ty, "u64")) return "i64";
    if (std.mem.eql(u8, ty, "usize")) return "isize";
    if (std.mem.eql(u8, ty, "f32")) return "f32";
    if (std.mem.eql(u8, ty, "f64")) return "f64";
    return null;
}

pub fn numericSelectTemps(ty: []const u8) NumericSelectTemps {
    if (std.mem.eql(u8, wasmType(ty), "i64")) {
        return .{ .left = NUMERIC_SELECT_LEFT_TMP_I64, .right = NUMERIC_SELECT_RIGHT_TMP_I64 };
    }
    return .{ .left = NUMERIC_SELECT_LEFT_TMP_I32, .right = NUMERIC_SELECT_RIGHT_TMP_I32 };
}

pub fn numericSelectLeftTmp(ty: []const u8) []const u8 {
    return numericSelectTemps(ty).left;
}

pub fn bitwiseWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "and")) return if (std.mem.eql(u8, wt, "i64")) "i64.and" else "i32.and";
    if (std.mem.eql(u8, name, "or")) return if (std.mem.eql(u8, wt, "i64")) "i64.or" else "i32.or";
    if (std.mem.eql(u8, name, "xor")) return if (std.mem.eql(u8, wt, "i64")) "i64.xor" else "i32.xor";
    if (std.mem.eql(u8, name, "shl")) return if (std.mem.eql(u8, wt, "i64")) "i64.shl" else "i32.shl";
    if (std.mem.eql(u8, name, "shr")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.shr_u" else "i64.shr_s";
        return if (isUnsignedScalar(ty)) "i32.shr_u" else "i32.shr_s";
    }
    if (std.mem.eql(u8, name, "rotl")) return if (std.mem.eql(u8, wt, "i64")) "i64.rotl" else "i32.rotl";
    if (std.mem.eql(u8, name, "rotr")) return if (std.mem.eql(u8, wt, "i64")) "i64.rotr" else "i32.rotr";
    return null;
}

pub fn countBitsWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "clz")) return if (std.mem.eql(u8, wt, "i64")) "i64.clz" else "i32.clz";
    if (std.mem.eql(u8, name, "ctz")) return if (std.mem.eql(u8, wt, "i64")) "i64.ctz" else "i32.ctz";
    if (std.mem.eql(u8, name, "popcnt")) return if (std.mem.eql(u8, wt, "i64")) "i64.popcnt" else "i32.popcnt";
    return null;
}

pub fn floatUnaryWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (!std.mem.eql(u8, wt, "f32") and !std.mem.eql(u8, wt, "f64")) return null;
    if (std.mem.eql(u8, name, "abs")) return if (std.mem.eql(u8, wt, "f32")) "f32.abs" else "f64.abs";
    if (std.mem.eql(u8, name, "neg")) return if (std.mem.eql(u8, wt, "f32")) "f32.neg" else "f64.neg";
    if (std.mem.eql(u8, name, "sqrt")) return if (std.mem.eql(u8, wt, "f32")) "f32.sqrt" else "f64.sqrt";
    if (std.mem.eql(u8, name, "ceil")) return if (std.mem.eql(u8, wt, "f32")) "f32.ceil" else "f64.ceil";
    if (std.mem.eql(u8, name, "floor")) return if (std.mem.eql(u8, wt, "f32")) "f32.floor" else "f64.floor";
    if (std.mem.eql(u8, name, "trunc")) return if (std.mem.eql(u8, wt, "f32")) "f32.trunc" else "f64.trunc";
    if (std.mem.eql(u8, name, "nearest")) return if (std.mem.eql(u8, wt, "f32")) "f32.nearest" else "f64.nearest";
    return null;
}

pub fn floatBinaryWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (!std.mem.eql(u8, wt, "f32") and !std.mem.eql(u8, wt, "f64")) return null;
    if (std.mem.eql(u8, name, "min")) return if (std.mem.eql(u8, wt, "f32")) "f32.min" else "f64.min";
    if (std.mem.eql(u8, name, "max")) return if (std.mem.eql(u8, wt, "f32")) "f32.max" else "f64.max";
    if (std.mem.eql(u8, name, "copysign")) return if (std.mem.eql(u8, wt, "f32")) "f32.copysign" else "f64.copysign";
    return null;
}

pub fn numericWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "add")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.add";
        if (std.mem.eql(u8, wt, "f32")) return "f32.add";
        if (std.mem.eql(u8, wt, "f64")) return "f64.add";
        return "i32.add";
    }
    if (std.mem.eql(u8, name, "sub")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.sub";
        if (std.mem.eql(u8, wt, "f32")) return "f32.sub";
        if (std.mem.eql(u8, wt, "f64")) return "f64.sub";
        return "i32.sub";
    }
    if (std.mem.eql(u8, name, "mul")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.mul";
        if (std.mem.eql(u8, wt, "f32")) return "f32.mul";
        if (std.mem.eql(u8, wt, "f64")) return "f64.mul";
        return "i32.mul";
    }
    if (std.mem.eql(u8, name, "div")) {
        if (std.mem.eql(u8, wt, "f32")) return "f32.div";
        if (std.mem.eql(u8, wt, "f64")) return "f64.div";
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.div_u" else "i64.div_s";
        return if (isUnsignedScalar(ty)) "i32.div_u" else "i32.div_s";
    }
    if (std.mem.eql(u8, name, "rem")) {
        if (std.mem.eql(u8, wt, "f32") or std.mem.eql(u8, wt, "f64")) return null;
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.rem_u" else "i64.rem_s";
        return if (isUnsignedScalar(ty)) "i32.rem_u" else "i32.rem_s";
    }
    return null;
}

pub fn scalarConvertWasmOp(source_ty: []const u8, target_ty: []const u8) ?[]const u8 {
    const source_wt = wasmType(source_ty);
    const target_wt = wasmType(target_ty);
    if (std.mem.eql(u8, source_wt, target_wt)) return null;

    if (std.mem.eql(u8, source_wt, "i32") and std.mem.eql(u8, target_wt, "i64")) {
        return if (isUnsignedScalar(source_ty)) "i64.extend_i32_u" else "i64.extend_i32_s";
    }
    if (std.mem.eql(u8, source_wt, "i64") and std.mem.eql(u8, target_wt, "i32")) return "i32.wrap_i64";

    if (std.mem.eql(u8, source_wt, "i32") and std.mem.eql(u8, target_wt, "f32")) {
        return if (isUnsignedScalar(source_ty)) "f32.convert_i32_u" else "f32.convert_i32_s";
    }
    if (std.mem.eql(u8, source_wt, "i32") and std.mem.eql(u8, target_wt, "f64")) {
        return if (isUnsignedScalar(source_ty)) "f64.convert_i32_u" else "f64.convert_i32_s";
    }
    if (std.mem.eql(u8, source_wt, "i64") and std.mem.eql(u8, target_wt, "f32")) {
        return if (isUnsignedScalar(source_ty)) "f32.convert_i64_u" else "f32.convert_i64_s";
    }
    if (std.mem.eql(u8, source_wt, "i64") and std.mem.eql(u8, target_wt, "f64")) {
        return if (isUnsignedScalar(source_ty)) "f64.convert_i64_u" else "f64.convert_i64_s";
    }

    if (std.mem.eql(u8, source_wt, "f32") and std.mem.eql(u8, target_wt, "i32")) {
        return if (isUnsignedScalar(target_ty)) "i32.trunc_f32_u" else "i32.trunc_f32_s";
    }
    if (std.mem.eql(u8, source_wt, "f32") and std.mem.eql(u8, target_wt, "i64")) {
        return if (isUnsignedScalar(target_ty)) "i64.trunc_f32_u" else "i64.trunc_f32_s";
    }
    if (std.mem.eql(u8, source_wt, "f64") and std.mem.eql(u8, target_wt, "i32")) {
        return if (isUnsignedScalar(target_ty)) "i32.trunc_f64_u" else "i32.trunc_f64_s";
    }
    if (std.mem.eql(u8, source_wt, "f64") and std.mem.eql(u8, target_wt, "i64")) {
        return if (isUnsignedScalar(target_ty)) "i64.trunc_f64_u" else "i64.trunc_f64_s";
    }

    if (std.mem.eql(u8, source_wt, "f32") and std.mem.eql(u8, target_wt, "f64")) return "f64.promote_f32";
    if (std.mem.eql(u8, source_wt, "f64") and std.mem.eql(u8, target_wt, "f32")) return "f32.demote_f64";
    return null;
}

pub fn memoryLoadWasmOp(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "load_u8")) return "i32.load8_u";
    if (std.mem.eql(u8, name, "load_i8")) return "i32.load8_s";
    if (std.mem.eql(u8, name, "load_u16_le")) return "i32.load16_u";
    if (std.mem.eql(u8, name, "load_i16_le")) return "i32.load16_s";
    if (std.mem.eql(u8, name, "load_u32_le")) return "i32.load";
    if (std.mem.eql(u8, name, "load_i32_le")) return "i32.load";
    if (std.mem.eql(u8, name, "load_u64_le")) return "i64.load";
    if (std.mem.eql(u8, name, "load_i64_le")) return "i64.load";
    return null;
}

pub fn memoryLoadByteWidth(name: []const u8) ?usize {
    if (std.mem.eql(u8, name, "load_u8")) return 1;
    if (std.mem.eql(u8, name, "load_i8")) return 1;
    if (std.mem.eql(u8, name, "load_u16_le")) return 2;
    if (std.mem.eql(u8, name, "load_i16_le")) return 2;
    if (std.mem.eql(u8, name, "load_u32_le")) return 4;
    if (std.mem.eql(u8, name, "load_i32_le")) return 4;
    if (std.mem.eql(u8, name, "load_u64_le")) return 8;
    if (std.mem.eql(u8, name, "load_i64_le")) return 8;
    return null;
}

pub fn appendTupleParamAbi(allocator: std.mem.Allocator, out: *std.ArrayList(u8), base: []const u8, tuple_ty: []const u8, ctx: CodegenContext) CodegenError!void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ base, idx });
        defer allocator.free(nested_base);
        if (isTupleTypeName(elem_ty)) {
            try appendTupleParamAbi(allocator, out, nested_base, elem_ty, ctx);
        } else {
            try appendFmt(allocator, out, " (param ${s} {s})", .{
                nested_base,
                codegenWasmType(ctx, elem_ty),
            });
        }
    }
}
