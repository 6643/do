//! Control-flow emit (body/if/loop/defer/guard).
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
const NilComparisonNarrowing = model.NilComparisonNarrowing;
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_collect_declarations = @import("codegen_collect_declarations.zig");
const gen_import = @import("gen_import.zig");
const hasBorrowedName = gen_import.hasBorrowedName;
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const emitWasiRecordReturnCall = gen_wasi_emit.emitWasiRecordReturnCall;
const gen_hooks = @import("gen_hooks.zig");
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
const loopSourceLocalName = context.loopSourceLocalName;
const NO_RESULT_ITEMS = model.NO_RESULT_ITEMS;
const EMPTY_LOCAL_SET = LocalSet{};
const DeferItem = context.DeferItem;
const SelfTailTco = context.SelfTailTco;
const RecvLoopHeader = context.RecvLoopHeader;
const CollectionLoopHeader = context.CollectionLoopHeader;
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
const gen_struct = @import("gen_struct.zig");
const gen_union_emit = @import("gen_union_emit.zig");
const gen_ownership = @import("gen_ownership.zig");
const OwnedLoopFrames = gen_ownership.OwnedLoopFrames;
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
pub fn collectDirectBodyLocals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) !void {
    try gen_hooks.collectBodyLocalsWithMode(allocator, tokens, start_idx, end_idx, ctx, out, false);
}

pub fn fieldReflectionLoopHeader(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    locals: *const LocalSet,
) ?FieldReflectionLoopHeader {
    _ = locals;
    if (start_idx + 8 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "loop")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, open_brace, "=") orelse return null;
    if (eq_idx != start_idx + 2) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    if (eq_idx + 5 != open_brace) return null;
    if (!std.mem.eql(u8, tokens[eq_idx + 1].lexeme, "fields")) return null;
    if (!tokEq(tokens[eq_idx + 2], "(")) return null;
    if (tokens[eq_idx + 3].kind != .ident) return null;
    if (!tokEq(tokens[eq_idx + 4], ")")) return null;
    const type_name = substituteGenericType(tokens[eq_idx + 3].lexeme, ctx.type_bindings);
    const decl = findStructDecl(ctx.structs, type_name) orelse return null;
    return .{
        .field_name = tokens[start_idx + 1].lexeme,
        .decl = decl,
        .loop_idx = start_idx,
        .open_brace = open_brace,
        .close_brace = close_brace,
    };
}

pub fn collectionLoopHeader(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    locals: *const LocalSet,
) ?CollectionLoopHeader {
    if (start_idx + 6 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "loop")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, open_brace, "=") orelse return null;
    const binds = parseCollectionLoopBinds(tokens, start_idx + 1, eq_idx) orelse return null;
    const source_start = eq_idx + 1;
    const source_end = open_brace;
    if (source_start >= source_end) return null;

    if (source_end == source_start + 1 and tokens[source_start].kind == .ident) {
        const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[source_start].lexeme) orelse return null;
        const elem_bytes = storageElementByteWidthForType(storage.elem_ty, ctx) orelse return null;
        return .{
            .value_name = binds.value_name,
            .index_name = binds.index_name,
            .source_name = tokens[source_start].lexeme,
            .source_ty = storage.ty,
            .source_start = source_start,
            .source_end = source_end,
            .elem_ty = storage.elem_ty,
            .elem_bytes = elem_bytes,
            .open_brace = open_brace,
            .close_brace = close_brace,
        };
    }

    const source_ty = inferExprType(tokens, source_start, source_end, locals, ctx) orelse return null;
    const elem_ty = storageElemTypeFromName(source_ty) orelse return null;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return null;
    return .{
        .value_name = binds.value_name,
        .index_name = binds.index_name,
        .source_name = "",
        .source_ty = source_ty,
        .source_start = source_start,
        .source_end = source_end,
        .source_is_expr = true,
        .elem_ty = elem_ty,
        .elem_bytes = elem_bytes,
        .open_brace = open_brace,
        .close_brace = close_brace,
    };
}

pub fn recvLoopHeader(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    locals: *const LocalSet,
) ?RecvLoopHeader {
    if (start_idx + 8 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "loop")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, open_brace, "=") orelse return null;
    if (eq_idx + 5 != open_brace) return null;
    if (!tokEq(tokens[eq_idx + 1], "recv")) return null;
    if (!tokEq(tokens[eq_idx + 2], "(")) return null;
    if (tokens[eq_idx + 3].kind != .ident) return null;
    if (!tokEq(tokens[eq_idx + 4], ")")) return null;
    const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[eq_idx + 3].lexeme) orelse return null;
    const elem_bytes = storageElementByteWidthForType(storage.elem_ty, ctx) orelse return null;
    const binds = parseRecvLoopBinds(tokens, start_idx + 1, eq_idx) orelse return null;
    return .{
        .value_name = binds.value_name,
        .count_name = binds.count_name,
        .source_name = tokens[eq_idx + 3].lexeme,
        .elem_ty = storage.elem_ty,
        .elem_bytes = elem_bytes,
        .open_brace = open_brace,
        .close_brace = close_brace,
    };
}

const CollectionLoopBinds = struct {
    value_name: ?[]const u8,
    index_name: ?[]const u8,
};

const RecvLoopBinds = struct {
    value_name: ?[]const u8,
    count_name: ?[]const u8,
};

pub fn parseCollectionLoopBinds(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?CollectionLoopBinds {
    if (start_idx + 3 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], ",")) return null;
    if (tokens[start_idx + 2].kind != .ident) return null;
    return .{
        .value_name = loopBindName(tokens[start_idx].lexeme),
        .index_name = loopBindName(tokens[start_idx + 2].lexeme),
    };
}

pub fn parseRecvLoopBinds(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?RecvLoopBinds {
    if (start_idx + 1 == end_idx) {
        if (tokens[start_idx].kind != .ident) return null;
        return .{
            .value_name = loopBindName(tokens[start_idx].lexeme),
            .count_name = null,
        };
    }
    if (start_idx + 3 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], ",")) return null;
    if (tokens[start_idx + 2].kind != .ident) return null;
    return .{
        .value_name = loopBindName(tokens[start_idx].lexeme),
        .count_name = loopBindName(tokens[start_idx + 2].lexeme),
    };
}

pub fn loopBindName(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "_")) return null;
    return name;
}

pub fn emitReturnStmt(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, self_tail_tco: ?*const SelfTailTco, out: *std.ArrayList(u8)) !bool {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "return")) return false;
    if (self_tail_tco) |tco| {
        if (try emitSelfTailReturn(allocator, tokens, start_idx, end_idx, locals, ctx, tco.*, out)) {
            return true;
        }
    }
    const expected_ty: ?[]const u8 = if (result_tys.len == 1) result_tys[0] else null;
    var move_names = std.ArrayList([]const u8).empty;
    defer move_names.deinit(allocator);

    const single_move_name = if (expected_ty) |ty|
        if (isManagedLocalType(ty, ctx)) directManagedLocalExprName(tokens, start_idx + 1, end_idx, locals, ctx) else null
    else
        null;
    if (single_move_name) |name| {
        try move_names.append(allocator, name);
        try appendFmt(allocator, out, "    ;; arc-return-move {s}\n", .{name});
    }
    if (result_union != null and try emitUnionReturn(allocator, tokens, start_idx, end_idx, locals, ctx, result_union.?, &move_names, defer_ctx, out)) {
        // Union value emitted as payload slots followed by runtime tag.
    } else if (try emitUnmanagedStructErrorUnionReturn(allocator, tokens, start_idx, end_idx, body_start, locals, ctx, result_tys, result_struct, defer_ctx, out)) {
        // Unmanaged struct plus error tag emitted as payload fields followed by status.
    } else if (try emitUnmanagedStructReturnLocal(allocator, tokens, start_idx, end_idx, locals, ctx, result_tys, result_struct, out)) {
        // Unmanaged struct fields emitted in declaration order.
    } else if (try emitTupleReturnLocal(allocator, tokens, start_idx, end_idx, locals, ctx, result_tys, result_items, out)) {
        // Tuple elements emitted as multi-value results in declaration order.
    } else if (try emitWasiRecordReturnCall(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, result_struct, out)) {
        // WIT record result fields emitted in declaration order.
    } else if (result_tys.len > 1 and try emitMultiResultReturnCall(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, defer_ctx, out)) {
        // Multi-result call passthrough emitted.
    } else if (result_tys.len > 1 and try emitTupleReturnExpr(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, result_items, out)) {
        // Tuple constructor or multi-value expression returned as flattened ABI values.
    } else if (result_tys.len > 1 and result_items.len != 0) {
        try emitMultiResultReturnValues(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_items, &move_names, out);
    } else if (result_tys.len > 1) {
        try emitMultiResultReturnAbiValues(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, &move_names, out);
    } else if (result_tys.len == 0 and start_idx + 2 == end_idx and tokEq(tokens[start_idx + 1], "nil")) {
        // `return nil` is the explicit spelling of an empty return in test/nil functions.
    } else if (start_idx + 1 < end_idx) {
        var emitted_move_call = false;
        var return_move_ctx: ?CallLastUseMoveContext = null;
        if (expected_ty) |ty| {
            if (isManagedLocalType(ty, ctx)) {
                return_move_ctx = .{
                    .body_start = body_start,
                    .stmt_end = end_idx,
                    .body_end = end_idx,
                    .defer_ctx = defer_ctx,
                    .allow_last_use_move = true,
                    .allow_field_read_move = true,
                };
                emitted_move_call = try emitManagedHandleCallExprWithMoveContext(
                    allocator,
                    tokens,
                    start_idx + 1,
                    end_idx,
                    end_idx,
                    true,
                    locals,
                    defer_ctx,
                    ctx,
                    ty,
                    out,
                );
            }
        }
        if (!emitted_move_call and !try gen_hooks.emitExprWithMoveContext(allocator, tokens, start_idx + 1, end_idx, locals, ctx, expected_ty, if (return_move_ctx) |*move_ctx| move_ctx else null, out)) {
            return error.NoMatchingCall;
        }
    }
    try emitDeferCleanupStack(allocator, tokens, defer_ctx, locals, ctx, out);
    if (return_label) |label| {
        try appendFmt(allocator, out, "    br ${s}\n", .{label});
    } else {
        const release_plan = try buildReturnOwnershipPlan(allocator, return_cleanup_locals, ctx, move_names.items);
        defer release_plan.deinit(allocator);
        try emitOwnershipReleasePlan(allocator, release_plan, out);
        try out.appendSlice(allocator, "    return\n");
    }
    return true;
}

pub fn emitSelfTailReturn(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, tco: SelfTailTco, out: *std.ArrayList(u8)) !bool {
    const range = trimParens(tokens, start_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    if (!same_callable_source_name(tco.func.source_name, publicDeclName(tokens[call_head.name_idx].lexeme))) return false;
    if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, tco.func)) return false;

    var arg_start = call_head.args_start;
    var param_idx: usize = 0;
    while (arg_start < call_head.args_end) {
        if (param_idx >= tco.func.params.len) return false;
        const param = tco.func.params[param_idx];
        if (param.callback != null or param.variadic) return false;
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        if (!try gen_hooks.emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param.ty, out)) {
            return error.NoMatchingCall;
        }
        try appendFmt(allocator, out, "    local.set $__tail_arg_{s}\n", .{param.name});
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx != tco.func.params.len) return false;

    for (tco.func.params) |param| {
        if (param.callback != null) continue;
        try appendFmt(allocator, out, "    local.get $__tail_arg_{s}\n", .{param.name});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{param.name});
    }
    try appendFmt(allocator, out, "    br ${s}\n", .{tco.loop_label});
    return true;
}

pub fn emitMultiResultReturnValues(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, result_items: []const FuncResultItem, move_names: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) CodegenError!void {
    var expr_start = start_idx;
    var item_idx: usize = 0;
    while (expr_start < end_idx) {
        if (item_idx >= result_items.len) return error.NoMatchingCall;
        const expr_end = findArgEnd(tokens, expr_start, end_idx);
        const item = result_items[item_idx];
        if (item.union_layout) |layout| {
            try collectUnionReturnMoveNames(allocator, tokens, expr_start, expr_end, locals, ctx, layout, move_names);
            if (!try gen_hooks.emitUnionValue(allocator, tokens, expr_start, expr_end, locals, ctx, layout, false, null, out)) {
                return error.NoMatchingCall;
            }
        } else {
            try emitSingleReturnAbiValue(allocator, tokens, expr_start, expr_end, locals, ctx, item.ty, move_names, null, out);
        }
        item_idx += 1;
        expr_start = expr_end;
        if (expr_start < end_idx and tokEq(tokens[expr_start], ",")) expr_start += 1;
    }
    if (item_idx != result_items.len) return error.NoMatchingCall;
}

pub fn emitMultiResultReturnAbiValues(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, move_names: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) CodegenError!void {
    var expr_start = start_idx;
    var result_idx: usize = 0;
    while (expr_start < end_idx) {
        if (result_idx >= result_tys.len) return error.NoMatchingCall;
        const expr_end = findArgEnd(tokens, expr_start, end_idx);
        try emitSingleReturnAbiValue(allocator, tokens, expr_start, expr_end, locals, ctx, result_tys[result_idx], move_names, null, out);
        result_idx += 1;
        expr_start = expr_end;
        if (expr_start < end_idx and tokEq(tokens[expr_start], ",")) expr_start += 1;
    }
    if (result_idx != result_tys.len) return error.NoMatchingCall;
}

pub fn emitSingleReturnAbiValue(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: []const u8, move_names: *std.ArrayList([]const u8), move_ctx: ?*const CallLastUseMoveContext, out: *std.ArrayList(u8)) CodegenError!void {
    if (try emitStorageAggReturnValue(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, out)) {
        return;
    }

    var copy_returned_managed_local = false;
    if (isManagedLocalType(expected_ty, ctx)) {
        if (directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx)) |name| {
            if (hasBorrowedName(move_names.items, name)) {
                copy_returned_managed_local = true;
                try appendFmt(allocator, out, "    ;; arc-return-copy {s}\n", .{name});
            } else {
                try move_names.append(allocator, name);
                try appendFmt(allocator, out, "    ;; arc-return-move {s}\n", .{name});
            }
        }
    }
    var emitted_move_call = false;
    if (isManagedLocalType(expected_ty, ctx)) {
        if (move_ctx) |ctx_info| {
            emitted_move_call = try emitManagedHandleCallExprWithMoveContext(
                allocator,
                tokens,
                start_idx,
                end_idx,
                ctx_info.body_end,
                ctx_info.allow_last_use_move,
                locals,
                ctx_info.defer_ctx,
                ctx,
                expected_ty,
                out,
            );
        }
    }
    if (!emitted_move_call and !try gen_hooks.emitExprWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, move_ctx, out)) {
        return error.NoMatchingCall;
    }
    if (copy_returned_managed_local) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
}

pub fn emitMultiResultReturnCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, defer_ctx: ?*const DeferContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != result_tys.len) return false;
    for (result_tys, 0..) |result_ty, i| {
        if (!std.mem.eql(u8, result_ty, func.results[i])) return false;
    }
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = end_idx,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    };
    return try gen_hooks.emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out);
}

pub fn collectLoopControlFrames(allocator: std.mem.Allocator, start: *const LoopControl, target: *const LoopControl, ctx: CodegenContext) !OwnedLoopFrames {
    var frames = std.ArrayList(ownership.LoopFrame).empty;
    errdefer {
        for (frames.items) |frame| {
            if (frame.locals.len != 0) allocator.free(frame.locals);
        }
        frames.deinit(allocator);
    }

    var cursor: ?*const LoopControl = start;
    while (cursor) |control| {
        const managed = try collectManagedOwnershipLocals(allocator, control.cleanup_locals, ctx);
        try frames.append(allocator, .{
            .locals = managed,
            .path_facts = .{},
        });
        if (sameLoopControl(control, target)) break;
        cursor = control.parent;
    }

    if (frames.items.len == 0) {
        frames.deinit(allocator);
        return .{ .frames = &.{} };
    }

    return .{
        .frames = try frames.toOwnedSlice(allocator),
    };
}

pub fn isDeadManagedAliasBinding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, stmt_end: usize, body_end: usize, locals: *const LocalSet, ctx: CodegenContext) CodegenError!bool {
    if (start_idx >= stmt_end or tokens[start_idx].kind != .ident) return false;
    const target_name = tokens[start_idx].lexeme;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, stmt_end, "=") orelse return false;
    if (tokenRangeUsesIdent(tokens, stmt_end, body_end, target_name)) return false;
    if (!isDirectManagedLocalExpr(tokens, eq_idx + 1, stmt_end, locals, ctx)) return false;
    if (storageBindingElemType(tokens, start_idx, stmt_end) != null) return true;
    if (managedPayloadBinding(tokens, start_idx, stmt_end) != null) return true;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const binding = (try typedStructBinding(allocator, tokens, start_idx, stmt_end, ctx, &owned_types)) orelse return false;
    return findStructLayout(ctx.struct_layouts, binding.ty) != null;
}

pub fn emitBody(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, self_tail_tco: ?*const SelfTailTco, out: *std.ArrayList(u8)) !void {
    const allow_call_arg_last_use_move = loop_ctx == null;
    var active_locals = try cloneLocalSet(allocator, locals);
    defer active_locals.deinit(allocator);
    const active = &active_locals;
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        var exit_defer_storage: DeferContext = undefined;
        const exit_defer_ctx: ?*const DeferContext = if (defer_ctx) |scope| blk: {
            exit_defer_storage = .{
                .parent = scope.parent,
                .start_idx = scope.start_idx,
                .end_idx = scope.end_idx,
                .registered_end_idx = i,
            };
            break :blk &exit_defer_storage;
        } else null;

        if (isDeferStmt(tokens, i, stmt_end)) {
            // Cleanup registration only; execution happens on block exit paths.
        } else if (try emitLoopControlStmt(allocator, tokens, i, stmt_end, active, control_cleanup_locals, loop_ctx, exit_defer_ctx, ctx, out)) {
            // Loop control emitted.
        } else if (try emitGuardLoopControlIf(allocator, tokens, i, stmt_end, active, control_cleanup_locals, loop_ctx, exit_defer_ctx, ctx, out)) {
            // Guard loop control emitted.
            try applyGuardLoopControlNarrowing(allocator, tokens, i, stmt_end, active, ctx);
        } else if (try emitLoopBlock(allocator, tokens, i, stmt_end, body_start, active, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out)) {
            // Loop block emitted.
        } else if (try emitIfBlock(allocator, tokens, i, stmt_end, body_start, active, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, self_tail_tco, out)) {
            // If block emitted.
            try applyIfBlockFallthroughNarrowing(allocator, tokens, i, stmt_end, active, ctx);
        } else if (try emitGuardReturnIf(allocator, tokens, i, stmt_end, end_idx, body_start, allow_call_arg_last_use_move, active, return_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, exit_defer_ctx, return_label, self_tail_tco, out)) {
            // Guard return emitted.
            try applyGuardReturnNilNarrowing(allocator, tokens, i, stmt_end, active);
            try applyGuardReturnIsNarrowing(allocator, tokens, i, stmt_end, active, ctx);
        } else if (try emitReturnStmt(allocator, tokens, i, stmt_end, body_start, active, return_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, exit_defer_ctx, return_label, self_tail_tco, out)) {
            // Return emitted.
        } else if (try emitDiscardAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Discard assignment emitted.
        } else if (try isDeadManagedAliasBinding(allocator, tokens, i, stmt_end, end_idx, active, ctx)) {
            // Dead managed alias binding elided.
        } else if (try emitUnionBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Union binding emitted.
        } else if (try gen_hooks.emitMultiResultAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Multi-result assignment emitted.
        } else if (try emitStructFieldMetaSetAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Struct field metadata assignment emitted.
        } else if (try emitStructSetAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Struct field assignment emitted.
        } else if (try emitStorageAssignment(allocator, tokens, i, stmt_end, start_idx, end_idx, active, exit_defer_ctx, ctx, out)) {
            // Storage assignment emitted.
        } else if (try emitManagedLocalAssignment(allocator, tokens, i, stmt_end, end_idx, active, exit_defer_ctx, ctx, out)) {
            // Managed handle assignment emitted.
        } else if (managedPayloadBinding(tokens, i, stmt_end) != null) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, start_idx, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out);
        } else if (storageBindingElemType(tokens, i, stmt_end) != null) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, start_idx, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out);
        } else if (isCollectedTypedStorageBinding(tokens, i, stmt_end, active)) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, start_idx, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out);
        } else if (try emitTupleBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Tuple field local binding emitted.
        } else if (try typedStructBindingDecl(allocator, tokens, i, stmt_end, ctx)) |decl| {
            try emitStructBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, decl, out);
        } else if (inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs)) |decl| {
            try emitStructBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, decl, out);
        } else if (inferredStructBinding(tokens, i, stmt_end, active, ctx)) |binding| {
            try emitStructBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, binding.decl, out);
        } else if (try emitScalarAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Scalar assignment emitted.
        } else if (typedScalarBindingType(tokens, i, stmt_end, ctx)) |scalar_ty| {
            const eq_idx = findTopLevelToken(tokens, i, stmt_end, "=") orelse {
                i = stmt_end;
                continue;
            };
            const emitted = try emitScalarCallExprWithMoveContext(
                allocator,
                tokens,
                eq_idx + 1,
                stmt_end,
                end_idx,
                allow_call_arg_last_use_move,
                active,
                exit_defer_ctx,
                ctx,
                scalar_ty,
                out,
            ) or try gen_hooks.emitExpr(allocator, tokens, eq_idx + 1, stmt_end, active, ctx, scalar_ty, out);
            if (!emitted) return error.NoMatchingCall;
            try appendFmt(allocator, out, "    local.set ${s}\n", .{resolvedLocalName(active.locals.items, tokens[i].lexeme)});
        } else if (try emitInferredScalarBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Inferred scalar binding emitted.
        } else if (try gen_hooks.emitBareUserFuncCallWithMoveContext(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Nil-return user function call emitted.
        } else if (try emitBareWasiHostImportCall(allocator, tokens, i, stmt_end, active, ctx, out, gen_hooks.emitExpr)) {
            // Statement-only WASI result-area call emitted.
        } else if (isHostImportCallExpr(tokens, i, stmt_end, ctx) or isWasiHostImportCallExpr(tokens, i, stmt_end, ctx)) {
            if (!try gen_hooks.emitExpr(allocator, tokens, i, stmt_end, active, ctx, null, out)) {
                return error.NoMatchingCall;
            }
        }
        clearNarrowedUnionLocalsForAssignments(tokens, i, stmt_end, active);
        i = stmt_end;
    }
    if (defer_ctx) |scope| {
        if (!bodyEndsWithPlainReturn(tokens, start_idx, end_idx)) {
            const normal_defer = DeferContext{
                .parent = scope.parent,
                .start_idx = scope.start_idx,
                .end_idx = scope.end_idx,
                .registered_end_idx = end_idx,
            };
            try emitDeferredCleanupsForContext(allocator, tokens, &normal_defer, locals, ctx, out);
        }
    }
}

pub fn isCollectedTypedStorageBinding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet) bool {
    if (start_idx + 3 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (tokEq(tokens[start_idx + 1], "=")) return false;
    if (findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return findTopLevelToken(tokens, start_idx + 1, end_idx, "=") != null;
}

pub fn isDiscardAssignment(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 3 > end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[start_idx].lexeme, "_")) return false;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    return eq_idx == start_idx + 1 and eq_idx + 1 < end_idx;
}

pub fn discardExprIsPureNoop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return true;
    if (range.end == range.start + 1) return true;
    if (isStorageAggLiteralExpr(tokens, range.start, range.end)) return true;
    return false;
}

pub fn emitDiscardStackValue(allocator: std.mem.Allocator, ty: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    if (isManagedLocalType(ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_dec\n");
    } else {
        try out.appendSlice(allocator, "    drop\n");
    }
}

fn emitDiscardMultiResultUserCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    rhs_start: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, rhs_start, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len <= 1) return false;

    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try gen_hooks.emitUserFuncCallWithMoveContext(
        allocator,
        tokens,
        call_head.args_start,
        call_head.args_end,
        locals,
        ctx,
        func,
        &move_ctx,
        out,
    )) return error.NoMatchingCall;

    var result_idx = func.results.len;
    while (result_idx > 0) {
        result_idx -= 1;
        try emitDiscardStackValue(allocator, func.results[result_idx], ctx, out);
    }
    return true;
}

pub fn emitDiscardAssignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!isDiscardAssignment(tokens, start_idx, end_idx)) return false;
    const eq_idx = start_idx + 1;
    const rhs_start = eq_idx + 1;
    if (discardExprIsPureNoop(tokens, rhs_start, end_idx)) return true;

    if (try gen_hooks.emitBareUserFuncCallWithMoveContext(allocator, tokens, rhs_start, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, out)) {
        return true;
    }
    if (try emitBareWasiHostImportCall(allocator, tokens, rhs_start, end_idx, locals, ctx, out, gen_hooks.emitExpr)) return true;

    if (try emitDiscardMultiResultUserCall(
        allocator,
        tokens,
        rhs_start,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        out,
    )) return true;

    const ty = inferExprType(tokens, rhs_start, end_idx, locals, ctx) orelse return error.NoMatchingCall;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try gen_hooks.emitExprWithMoveContext(allocator, tokens, rhs_start, end_idx, locals, ctx, ty, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    try emitDiscardStackValue(allocator, ty, ctx, out);
    return true;
}

pub fn emitDeferCleanupStack(allocator: std.mem.Allocator, tokens: []const lexer.Token, defer_ctx: ?*const DeferContext, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    const scope = defer_ctx orelse return;
    try emitDeferredCleanupsForContext(allocator, tokens, scope, locals, ctx, out);
    try emitDeferCleanupStack(allocator, tokens, scope.parent, locals, ctx, out);
}

pub fn emitDeferCleanupStackThrough(allocator: std.mem.Allocator, tokens: []const lexer.Token, defer_ctx: ?*const DeferContext, stop_ctx: *const DeferContext, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    var cursor = defer_ctx;
    while (cursor) |scope| {
        try emitDeferredCleanupsForContext(allocator, tokens, scope, locals, ctx, out);
        if (sameDeferScope(scope, stop_ctx)) return;
        cursor = scope.parent;
    }
    try emitDeferredCleanupsForContext(allocator, tokens, stop_ctx, locals, ctx, out);
}

pub fn applyIfBlockFallthroughNarrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return;
    if (bodyCanReachEnd(tokens, open_brace + 1, close_brace)) return;
    try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, locals, ctx, false);
}

pub fn sameDeferScope(a: *const DeferContext, b: *const DeferContext) bool {
    return a.start_idx == b.start_idx and a.end_idx == b.end_idx;
}

pub fn emitDeferredCleanupsForContext(allocator: std.mem.Allocator, tokens: []const lexer.Token, defer_ctx: *const DeferContext, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    const scan_end = @min(defer_ctx.registered_end_idx, defer_ctx.end_idx);
    var items = std.ArrayList(DeferItem).empty;
    defer items.deinit(allocator);

    var i = defer_ctx.start_idx;
    while (i < scan_end) {
        const stmt_end = findStmtEnd(tokens, i, defer_ctx.end_idx);
        if (parseDeferItem(tokens, i, stmt_end)) |item| {
            try items.append(allocator, item);
        }
        i = stmt_end;
    }

    var idx = items.items.len;
    while (idx > 0) {
        idx -= 1;
        try emitDeferCleanupItem(allocator, tokens, items.items[idx], locals, ctx, out);
    }
}

pub fn parseDeferItem(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?DeferItem {
    if (!isDeferStmt(tokens, start_idx, end_idx)) return null;
    const body_idx = start_idx + 1;
    if (tokEq(tokens[body_idx], "{")) {
        const close_brace = findMatchingInRange(tokens, body_idx, "{", "}", end_idx) catch return null;
        return .{
            .kind = .block,
            .start_idx = body_idx,
            .end_idx = close_brace,
        };
    }
    return .{
        .kind = .call,
        .start_idx = body_idx,
        .end_idx = end_idx,
    };
}

pub fn emitDeferCleanupItem(allocator: std.mem.Allocator, tokens: []const lexer.Token, item: DeferItem, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    switch (item.kind) {
        .call => try emitDeferCleanupCall(allocator, tokens, item.start_idx, item.end_idx, locals, ctx, out),
        .block => try emitDeferCleanupBlock(allocator, tokens, item.start_idx, item.end_idx, locals, ctx, out),
    }
}

pub fn emitDeferCleanupCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return error.NoMatchingCall;
    if (call_head.is_intrinsic) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    ;; defer-cleanup-call {s}\n", .{tokens[call_head.name_idx].lexeme});

    if (try gen_hooks.emitBareUserFuncCall(allocator, tokens, start_idx, end_idx, locals, ctx, out)) return;
    if (try emitBareWasiHostImportCall(allocator, tokens, start_idx, end_idx, locals, ctx, out, gen_hooks.emitExpr)) return;
    if (isHostImportCallExpr(tokens, start_idx, end_idx, ctx) or isWasiHostImportCallExpr(tokens, start_idx, end_idx, ctx)) {
        if (!try gen_hooks.emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, null, out)) {
            return error.NoMatchingCall;
        }
        return;
    }
    return error.NoMatchingCall;
}

pub fn emitDeferCleanupBlock(allocator: std.mem.Allocator, tokens: []const lexer.Token, open_brace: usize, close_brace: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    try out.appendSlice(allocator, "    ;; defer-cleanup-block\n");
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collectDirectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &cleanup_locals);

    const no_results: []const []const u8 = &.{};
    const cleanup_defer = DeferContext{
        .parent = null,
        .start_idx = open_brace + 1,
        .end_idx = close_brace,
        .registered_end_idx = close_brace,
    };
    try out.appendSlice(allocator, "    block $defer_cleanup_exit\n");
    try emitBody(allocator, tokens, open_brace + 1, close_brace, open_brace + 1, locals, &cleanup_locals, &EMPTY_LOCAL_SET, ctx, no_results, NO_RESULT_ITEMS, null, null, null, &cleanup_defer, "defer_cleanup_exit", null, out);
    try out.appendSlice(allocator, "    end\n");
    try emitBlockReleaseManagedLocals(allocator, &cleanup_locals, ctx, out);
}

pub fn emitManagedLocalAssignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!isManagedLocalAssignmentStmt(tokens, start_idx, end_idx, locals, ctx)) return false;
    const target_name = tokens[start_idx].lexeme;
    const target_local_name = findLocalName(locals.locals.items, target_name) orelse return false;
    const target_ty = findLocalType(locals.locals.items, target_name) orelse return false;
    const rhs_start = start_idx + 2;

    if (end_idx == rhs_start + 1 and tokens[rhs_start].kind == .ident) {
        if (directManagedLocalExprName(tokens, rhs_start, end_idx, locals, ctx)) |actual_name| {
            if (std.mem.eql(u8, actual_name, target_local_name)) return true;
        }
    }

    if (!try gen_hooks.emitExpr(allocator, tokens, rhs_start, end_idx, locals, ctx, target_ty, out)) {
        return error.NoMatchingCall;
    }
    const move_source = directManagedLastUseMoveSource(tokens, rhs_start, end_idx, body_end, target_name, locals, ctx, defer_ctx);
    if (move_source == null and isDirectManagedLocalExpr(tokens, rhs_start, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_local_name, out);
    if (move_source) |source| {
        try appendFmt(allocator, out, "    ;; arc-overwrite-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

pub fn emitScalarCallExprWithMoveContext(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
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

pub fn emitScalarAssignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;

    const target_ty = findLocalType(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    const target_name = findLocalName(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!isCodegenScalarType(ctx, target_ty)) return false;
    if (!try emitScalarCallExprWithMoveContext(allocator, tokens, start_idx + 2, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, target_ty, out) and
        !try gen_hooks.emitExpr(allocator, tokens, start_idx + 2, end_idx, locals, ctx, target_ty, out))
    {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
    return true;
}

pub fn emitInferredScalarBinding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const ty = inferredScalarBindingType(tokens, start_idx, end_idx, locals, ctx) orelse return false;
    if (!try emitScalarCallExprWithMoveContext(allocator, tokens, start_idx + 2, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, ty, out) and
        !try gen_hooks.emitExpr(allocator, tokens, start_idx + 2, end_idx, locals, ctx, ty, out))
    {
        return error.NoMatchingCall;
    }
    const target_name = findLocalName(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
    return true;
}

pub fn appendNilComparisonNarrowingForBranch(allocator: std.mem.Allocator, tokens: []const lexer.Token, cond_start: usize, cond_end: usize, locals: *LocalSet, branch_is_true: bool) !void {
    const narrowing = nilComparisonNarrowing(tokens, cond_start, cond_end, locals) orelse return;
    if (narrowing.non_nil_when_true != branch_is_true) return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
}

pub fn appendConditionNarrowingForBranch(allocator: std.mem.Allocator, tokens: []const lexer.Token, cond_start: usize, cond_end: usize, locals: *LocalSet, ctx: CodegenContext, branch_is_true: bool) !void {
    try appendNilComparisonNarrowingForBranch(allocator, tokens, cond_start, cond_end, locals, branch_is_true);
    const narrowing = try isComparisonNarrowing(allocator, tokens, cond_start, cond_end, locals, ctx) orelse return;
    if (branch_is_true) {
        try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
    } else {
        const payload_ty = unionLocalSingleRemainingPayloadType(narrowing.union_local, narrowing.payload_ty) orelse return;
        try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
    }
}

pub fn isHostImportCallExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start + 2 > range.end) return false;
    if (tokens[range.start].kind != .ident) return false;
    if (findHostImportForTokens(ctx.host_imports, tokens, tokens[range.start].lexeme) == null) return false;
    if (!tokEq(tokens[range.start + 1], "(")) return false;
    const close_paren = findMatchingInRange(tokens, range.start + 1, "(", ")", range.end) catch return false;
    return close_paren + 1 == range.end;
}

pub fn isWasiHostImportCallExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start + 2 > range.end) return false;
    if (tokens[range.start].kind != .ident) return false;
    if (findWasiHostImportForTokens(ctx, tokens, tokens[range.start].lexeme) == null) return false;
    if (!tokEq(tokens[range.start + 1], "(")) return false;
    const close_paren = findMatchingInRange(tokens, range.start + 1, "(", ")", range.end) catch return false;
    return close_paren + 1 == range.end;
}

const TokenRange = struct {
    tokens: []const lexer.Token,
    start: usize,
    end: usize,
};

pub fn typedScalarBindingType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) ?[]const u8 {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const ty = substituteGenericType(tokens[start_idx + 1].lexeme, ctx.type_bindings);
    if (!isCodegenScalarOrErrorType(tokens, ctx, ty)) return null;
    if (findTopLevelToken(tokens, start_idx + 2, end_idx, "=") == null) return null;
    return ty;
}

pub fn inferredScalarBindingType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const ty = inferExprType(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    if (!isCodegenScalarType(ctx, ty)) return null;
    return ty;
}

pub fn isManagedLocalAssignmentStmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) bool {
    if (start_idx + 2 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;
    const target_ty = findLocalType(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    return isManagedLocalType(target_ty, ctx);
}

pub fn typedStructBindingDecl(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) CodegenError!?StructDecl {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const binding = (try typedStructBinding(allocator, tokens, start_idx, end_idx, ctx, &owned_types)) orelse return null;
    return binding.decl;
}

pub fn inferredStructCtorBinding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
) ?StructDecl {
    if (start_idx + 4 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    if (tokens[start_idx + 2].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 3], "{")) return null;
    const close_brace = findMatchingInRange(tokens, start_idx + 3, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    return findStructDecl(structs, tokens[start_idx + 2].lexeme);
}

pub fn clearNarrowedUnionLocalsForAssignments(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet) void {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return;
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end == lhs_start + 1 and tokens[lhs_start].kind == .ident) {
            clearNarrowedUnionLocal(locals, tokens[lhs_start].lexeme);
        }
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
}

pub fn clearNarrowedUnionLocal(locals: *LocalSet, name: []const u8) void {
    var i = locals.narrowed_union_locals.items.len;
    while (i > 0) {
        i -= 1;
        const local = locals.narrowed_union_locals.items[i];
        if (localNameMatches(local.name, local.source_name, name)) {
            _ = locals.narrowed_union_locals.orderedRemove(i);
        }
    }
}

pub fn emitGuardReturnIf(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, body_start: usize, allow_last_use_move: bool, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, self_tail_tco: ?*const SelfTailTco, out: *std.ArrayList(u8)) !bool {
    _ = result_struct;
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;

    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return false;
    const has_return_expr = return_idx + 1 < end_idx;
    var move_names = std.ArrayList([]const u8).empty;
    defer move_names.deinit(allocator);

    const cond_move_ctx = CallLastUseMoveContext{
        .body_start = body_start,
        .stmt_end = return_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    const emitted = try gen_hooks.emitExprWithMoveContext(allocator, tokens, start_idx + 1, return_idx, locals, ctx, "bool", &cond_move_ctx, out);
    if (!emitted) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    if\n");
    var return_active_locals = try cloneLocalSet(allocator, locals);
    defer return_active_locals.deinit(allocator);
    try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, return_idx, &return_active_locals, ctx, true);
    if (self_tail_tco) |tco| {
        if (try emitSelfTailReturn(allocator, tokens, return_idx, end_idx, &return_active_locals, ctx, tco.*, out)) {
            try out.appendSlice(allocator, "    end\n");
            return true;
        }
    }
    if (has_return_expr) {
        if (result_union) |layout| {
            try collectUnionReturnMoveNames(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, layout, &move_names);
            const move_ctx = CallLastUseMoveContext{
                .body_start = body_start,
                .stmt_end = end_idx,
                .body_end = end_idx,
                .defer_ctx = defer_ctx,
                .allow_last_use_move = true,
                .allow_field_read_move = true,
            };
            if (!try gen_hooks.emitUnionValue(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, layout, false, &move_ctx, out)) {
                return error.NoMatchingCall;
            }
        } else if (result_tys.len > 1 and result_items.len != 0) {
            try emitMultiResultReturnValues(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, result_items, &move_names, out);
        } else if (result_tys.len > 1) {
            try emitMultiResultReturnAbiValues(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, result_tys, &move_names, out);
        } else {
            if (result_tys.len != 1) return error.NoMatchingCall;
            const move_ctx = CallLastUseMoveContext{
                .body_start = body_start,
                .stmt_end = end_idx,
                .body_end = end_idx,
                .defer_ctx = defer_ctx,
                .allow_last_use_move = true,
                .allow_field_read_move = true,
            };
            try emitSingleReturnAbiValue(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, result_tys[0], &move_names, &move_ctx, out);
        }
    } else if (result_tys.len != 0) {
        return error.NoMatchingCall;
    }
    try emitDeferCleanupStack(allocator, tokens, defer_ctx, locals, ctx, out);
    if (return_label) |label| {
        try appendFmt(allocator, out, "      br ${s}\n", .{label});
    } else {
        try out.appendSlice(allocator, "      ;; arc-guard-return-release\n");
        const release_plan = try buildGuardReturnOwnershipPlan(allocator, return_cleanup_locals, ctx, move_names.items);
        defer release_plan.deinit(allocator);
        try emitOwnershipReleasePlan(allocator, release_plan, out);
        try out.appendSlice(allocator, "      return\n");
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn emitLoopBlock(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "loop")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;
    const loop_label = labelForLoopStart(tokens, start_idx);
    if (fieldReflectionLoopHeader(tokens, start_idx, end_idx, ctx, locals)) |header| {
        return try emitFieldReflectionLoopBlock(allocator, tokens, header, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
    if (collectionLoopHeader(tokens, start_idx, end_idx, ctx, locals)) |header| {
        return try emitCollectionLoopBlock(allocator, tokens, start_idx, header, body_start, loop_label, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
    if (recvLoopHeader(tokens, start_idx, end_idx, ctx, locals)) |header| {
        return try emitRecvLoopBlock(allocator, tokens, start_idx, header, body_start, loop_label, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
    if (open_brace != start_idx + 1) {
        return error.UnsupportedExpr;
    }

    const break_label = try std.fmt.allocPrint(allocator, "__loop_break_{d}", .{start_idx});
    defer allocator.free(break_label);
    const body_label = try std.fmt.allocPrint(allocator, "__loop_body_{d}", .{start_idx});
    defer allocator.free(body_label);

    try out.appendSlice(allocator, "    ;; loop-block\n");
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    try appendFmt(allocator, out, "    loop ${s}\n", .{body_label});
    var loop_locals = LocalSet{};
    defer loop_locals.deinit(allocator);
    try collectDirectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &loop_locals);
    var parent_defer_storage: DeferContext = undefined;
    const parent_defer_ptr: ?*const DeferContext = if (defer_ctx) |scope| blk: {
        parent_defer_storage = .{
            .parent = scope.parent,
            .start_idx = scope.start_idx,
            .end_idx = scope.end_idx,
            .registered_end_idx = start_idx,
        };
        break :blk &parent_defer_storage;
    } else null;
    const loop_defer = DeferContext{
        .parent = parent_defer_ptr,
        .start_idx = open_brace + 1,
        .end_idx = close_brace,
        .registered_end_idx = close_brace,
    };
    const nested_loop = LoopControl{
        .parent = if (loop_ctx) |*control| control else null,
        .source_label = loop_label,
        .break_label = break_label,
        .continue_label = body_label,
        .cleanup_locals = &loop_locals,
        .defer_ctx = &loop_defer,
    };
    var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &loop_locals);
    defer active_return_cleanup_locals.deinit(allocator);
    try emitBody(allocator, tokens, open_brace + 1, close_brace, body_start, locals, &active_return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, nested_loop, &loop_defer, return_label, null, out);
    if (bodyCanReachEnd(tokens, open_brace + 1, close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &loop_locals, ctx, out);
        try appendFmt(allocator, out, "    br ${s}\n", .{body_label});
    }
    try out.appendSlice(allocator, "    end\n");
    try out.appendSlice(allocator, "    end\n");
    if (!loopBodyCanBreakCurrentLoop(tokens, open_brace + 1, close_brace, loop_label)) {
        try out.appendSlice(allocator, "    unreachable\n");
    }
    return true;
}

pub fn emitCollectionLoopBlock(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, header: CollectionLoopHeader, body_start: usize, loop_label: ?[]const u8, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, parent_loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    const break_label = try std.fmt.allocPrint(allocator, "__loop_break_{d}", .{start_idx});
    defer allocator.free(break_label);
    const body_label = try std.fmt.allocPrint(allocator, "__loop_body_{d}", .{start_idx});
    defer allocator.free(body_label);
    const continue_label = try std.fmt.allocPrint(allocator, "__loop_continue_{d}", .{start_idx});
    defer allocator.free(continue_label);
    const index_local = try std.fmt.allocPrint(allocator, "__loop_index_{d}", .{start_idx});
    defer allocator.free(index_local);
    const owned_source_name = if (header.source_is_expr) try loopSourceLocalName(allocator, start_idx) else null;
    defer if (owned_source_name) |name| allocator.free(name);
    const source_name = owned_source_name orelse header.source_name;
    var loop_header = header;
    loop_header.source_name = source_name;

    if (header.source_is_expr) {
        if (!try gen_hooks.emitExpr(allocator, tokens, header.source_start, header.source_end, locals, ctx, header.source_ty, out)) {
            return error.NoMatchingCall;
        }
        if (isDirectManagedLocalExpr(tokens, header.source_start, header.source_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source_name});
    }

    try out.appendSlice(allocator, "    ;; loop-collection\n");
    try out.appendSlice(allocator, "    i32.const 0\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{index_local});
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    try appendFmt(allocator, out, "    loop ${s}\n", .{body_label});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{index_local});
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.ge_u\n");
    try appendFmt(allocator, out, "    br_if ${s}\n", .{break_label});
    try emitCollectionLoopBindings(allocator, loop_header, index_local, ctx, out);
    try appendFmt(allocator, out, "    block ${s}\n", .{continue_label});

    var loop_locals = LocalSet{};
    defer loop_locals.deinit(allocator);
    if (header.value_name) |value_name| {
        if (isManagedLocalType(header.elem_ty, ctx)) {
            try loop_locals.appendBorrowedLocalWithOrigin(allocator, value_name, header.elem_ty, false, .collection_value);
        }
    }
    try collectDirectBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &loop_locals);
    var parent_defer_storage: DeferContext = undefined;
    const parent_defer_ptr: ?*const DeferContext = if (defer_ctx) |scope| blk: {
        parent_defer_storage = .{
            .parent = scope.parent,
            .start_idx = scope.start_idx,
            .end_idx = scope.end_idx,
            .registered_end_idx = start_idx,
        };
        break :blk &parent_defer_storage;
    } else null;
    const loop_defer = DeferContext{
        .parent = parent_defer_ptr,
        .start_idx = header.open_brace + 1,
        .end_idx = header.close_brace,
        .registered_end_idx = header.close_brace,
    };
    const nested_loop = LoopControl{
        .parent = if (parent_loop_ctx) |*control| control else null,
        .source_label = loop_label,
        .break_label = break_label,
        .continue_label = continue_label,
        .cleanup_locals = &loop_locals,
        .defer_ctx = &loop_defer,
    };
    var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &loop_locals);
    defer active_return_cleanup_locals.deinit(allocator);
    try emitBody(allocator, tokens, header.open_brace + 1, header.close_brace, body_start, locals, &active_return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, nested_loop, &loop_defer, return_label, null, out);
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &loop_locals, ctx, out);
    }
    try out.appendSlice(allocator, "    end\n");
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{index_local});
        try out.appendSlice(allocator, "    i32.const 1\n");
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{index_local});
        try appendFmt(allocator, out, "    br ${s}\n", .{body_label});
    }
    try out.appendSlice(allocator, "    end\n");
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn emitCollectionLoopBindings(allocator: std.mem.Allocator, header: CollectionLoopHeader, index_local: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    if (header.index_name) |index_name| {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{index_local});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{index_name});
    }
    if (header.value_name) |value_name| {
        if (isTupleTypeName(header.elem_ty)) {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, index_local, header.elem_bytes);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, header.elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
            try emitTupleLocalSet(allocator, value_name, header.elem_ty, ctx, out);
        } else {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, index_local, header.elem_bytes);
            try appendLoadForPayloadType(allocator, out, header.elem_ty);
            if (isManagedLocalType(header.elem_ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{value_name});
        }
    }
}

pub fn emitRecvLoopBlock(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, header: RecvLoopHeader, body_start: usize, loop_label: ?[]const u8, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, parent_loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, out: *std.ArrayList(u8)) CodegenError!bool {
    const break_label = try std.fmt.allocPrint(allocator, "__loop_break_{d}", .{start_idx});
    defer allocator.free(break_label);
    const body_label = try std.fmt.allocPrint(allocator, "__loop_body_{d}", .{start_idx});
    defer allocator.free(body_label);
    const continue_label = try std.fmt.allocPrint(allocator, "__loop_continue_{d}", .{start_idx});
    defer allocator.free(continue_label);
    const count_local = try std.fmt.allocPrint(allocator, "__loop_count_{d}", .{start_idx});
    defer allocator.free(count_local);

    try out.appendSlice(allocator, "    ;; loop-recv\n");
    try out.appendSlice(allocator, "    i32.const 0\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{count_local});
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    try appendFmt(allocator, out, "    loop ${s}\n", .{body_label});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{count_local});
    try emitStorageLenPtr(allocator, out, header.source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.ge_u\n");
    try appendFmt(allocator, out, "    br_if ${s}\n", .{break_label});
    try emitRecvLoopBindings(allocator, header, count_local, ctx, out);
    try appendFmt(allocator, out, "    block ${s}\n", .{continue_label});

    var loop_locals = LocalSet{};
    defer loop_locals.deinit(allocator);
    if (header.value_name) |value_name| {
        if (isManagedLocalType(header.elem_ty, ctx)) {
            try loop_locals.appendBorrowedLocalWithOrigin(allocator, value_name, header.elem_ty, false, .recv_value);
        }
    }
    try collectDirectBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &loop_locals);
    var parent_defer_storage: DeferContext = undefined;
    const parent_defer_ptr: ?*const DeferContext = if (defer_ctx) |scope| blk: {
        parent_defer_storage = .{
            .parent = scope.parent,
            .start_idx = scope.start_idx,
            .end_idx = scope.end_idx,
            .registered_end_idx = start_idx,
        };
        break :blk &parent_defer_storage;
    } else null;
    const loop_defer = DeferContext{
        .parent = parent_defer_ptr,
        .start_idx = header.open_brace + 1,
        .end_idx = header.close_brace,
        .registered_end_idx = header.close_brace,
    };
    const nested_loop = LoopControl{
        .parent = if (parent_loop_ctx) |*control| control else null,
        .source_label = loop_label,
        .break_label = break_label,
        .continue_label = continue_label,
        .cleanup_locals = &loop_locals,
        .defer_ctx = &loop_defer,
    };
    var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &loop_locals);
    defer active_return_cleanup_locals.deinit(allocator);
    try emitBody(allocator, tokens, header.open_brace + 1, header.close_brace, body_start, locals, &active_return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, nested_loop, &loop_defer, return_label, null, out);
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &loop_locals, ctx, out);
    }
    try out.appendSlice(allocator, "    end\n");
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{count_local});
        try out.appendSlice(allocator, "    i32.const 1\n");
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{count_local});
        try appendFmt(allocator, out, "    br ${s}\n", .{body_label});
    }
    try out.appendSlice(allocator, "    end\n");
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn emitRecvLoopBindings(allocator: std.mem.Allocator, header: RecvLoopHeader, count_local: []const u8, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!void {
    if (header.count_name) |count_name| {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{count_local});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{count_name});
    }
    if (header.value_name) |value_name| {
        if (isTupleTypeName(header.elem_ty)) {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, count_local, header.elem_bytes);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, header.elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
            try emitTupleLocalSet(allocator, value_name, header.elem_ty, ctx, out);
        } else {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, count_local, header.elem_bytes);
            try appendLoadForPayloadType(allocator, out, header.elem_ty);
            if (isManagedLocalType(header.elem_ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{value_name});
        }
    }
}

pub fn emitLoopControlStmt(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, control_cleanup_locals: *const LocalSet, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    if (tokens[start_idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "break") or std.mem.eql(u8, tokens[start_idx].lexeme, "continue")) {
        if (!validLoopControlTail(tokens, start_idx, end_idx)) return error.UnsupportedExpr;
    } else {
        return false;
    }
    try emitLoopControlJump(allocator, tokens, start_idx, end_idx, loop_ctx, defer_ctx, locals, control_cleanup_locals, ctx, out);
    return true;
}

pub fn emitGuardLoopControlIf(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, control_cleanup_locals: *const LocalSet, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return false;
    if (!validLoopControlTail(tokens, control_idx, end_idx)) return error.UnsupportedExpr;
    if (!try gen_hooks.emitExpr(allocator, tokens, start_idx + 1, control_idx, locals, ctx, "bool", out)) {
        return error.NoMatchingCall;
    }
    try out.appendSlice(allocator, "    if\n");
    try emitLoopControlJump(allocator, tokens, control_idx, end_idx, loop_ctx, defer_ctx, locals, control_cleanup_locals, ctx, out);
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn emitLoopControlJump(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const current_control = if (loop_ctx) |*control| control else return error.NoMatchingCall;
    const control = resolveLoopControl(tokens, start_idx, end_idx, current_control) orelse return error.NoMatchingCall;
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "break")) {
        try emitDeferCleanupStackThrough(allocator, tokens, defer_ctx, control.defer_ctx, locals, ctx, out);
        try out.appendSlice(allocator, "    ;; loop-break-release\n");
        try emitBlockReleaseManagedLocals(allocator, control_cleanup_locals, ctx, out);
        try emitLoopControlReleaseChain(allocator, current_control, control, ctx, .break_stmt, out);
        try appendFmt(allocator, out, "    br ${s}\n", .{control.break_label});
        return;
    }
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "continue")) {
        try emitDeferCleanupStackThrough(allocator, tokens, defer_ctx, control.defer_ctx, locals, ctx, out);
        try out.appendSlice(allocator, "    ;; loop-continue-release\n");
        try emitBlockReleaseManagedLocals(allocator, control_cleanup_locals, ctx, out);
        try emitLoopControlReleaseChain(allocator, current_control, control, ctx, .continue_stmt, out);
        try appendFmt(allocator, out, "    br ${s}\n", .{control.continue_label});
        return;
    }
    return error.NoMatchingCall;
}

pub fn validLoopControlTail(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (end_idx == start_idx + 1) return true;
    return end_idx == start_idx + 3 and tokEq(tokens[start_idx + 1], "#") and tokens[start_idx + 2].kind == .ident;
}

pub fn resolveLoopControl(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first: *const LoopControl,
) ?*const LoopControl {
    if (end_idx == start_idx + 1) return first;
    const target_label = tokens[start_idx + 2].lexeme;
    var cursor: ?*const LoopControl = first;
    while (cursor) |control| {
        if (control.source_label) |label| {
            if (std.mem.eql(u8, label, target_label)) return control;
        }
        cursor = control.parent;
    }
    return null;
}

pub fn emitLoopControlReleaseChain(allocator: std.mem.Allocator, start: *const LoopControl, target: *const LoopControl, ctx: CodegenContext, kind: ownership.ExitKind, out: *std.ArrayList(u8)) !void {
    const frames = try collectLoopControlFrames(allocator, start, target, ctx);
    defer frames.deinit(allocator);
    const release_plan = try ownership.buildLoopControlExitPlan(allocator, kind, frames.frames);
    defer release_plan.deinit(allocator);
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

pub fn emitIfBlock(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, locals: *const LocalSet, return_cleanup_locals: *const LocalSet, control_cleanup_locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_items: []const FuncResultItem, result_struct: ?[]const u8, result_union: ?UnionLayout, loop_ctx: ?LoopControl, defer_ctx: ?*const DeferContext, return_label: ?[]const u8, self_tail_tco: ?*const SelfTailTco, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 4 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;

    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    var else_if_start: ?usize = null;
    var else_open: ?usize = null;
    var else_close: ?usize = null;
    if (close_brace + 1 < end_idx and tokEq(tokens[close_brace + 1], "else")) {
        if (close_brace + 2 >= end_idx) return false;
        if (tokEq(tokens[close_brace + 2], "if")) {
            else_if_start = close_brace + 2;
        } else if (tokEq(tokens[close_brace + 2], "{")) {
            const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return false;
            if (close_else + 1 != end_idx) return false;
            else_open = close_brace + 2;
            else_close = close_else;
        } else {
            return false;
        }
    } else if (close_brace + 1 != end_idx) {
        return false;
    }

    if (else_if_start != null) {
        try out.appendSlice(allocator, "    ;; if-else-if-block\n");
    } else if (else_open != null) {
        try out.appendSlice(allocator, "    ;; if-else-block\n");
    } else {
        try out.appendSlice(allocator, "    ;; if-block\n");
    }
    const emitted = try gen_hooks.emitExpr(allocator, tokens, start_idx + 1, open_brace, locals, ctx, "bool", out);
    if (!emitted) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    if\n");
    var then_locals = LocalSet{};
    defer then_locals.deinit(allocator);
    try collectDirectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &then_locals);
    var parent_defer_storage: DeferContext = undefined;
    const parent_defer_ptr: ?*const DeferContext = if (defer_ctx) |scope| blk: {
        parent_defer_storage = .{
            .parent = scope.parent,
            .start_idx = scope.start_idx,
            .end_idx = scope.end_idx,
            .registered_end_idx = start_idx,
        };
        break :blk &parent_defer_storage;
    } else null;
    const then_defer = DeferContext{
        .parent = parent_defer_ptr,
        .start_idx = open_brace + 1,
        .end_idx = close_brace,
        .registered_end_idx = close_brace,
    };
    var then_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &then_locals);
    defer then_return_cleanup_locals.deinit(allocator);
    var then_control_cleanup_locals = try mergeReturnCleanupLocals(allocator, control_cleanup_locals, &then_locals);
    defer then_control_cleanup_locals.deinit(allocator);
    var then_active_locals = try cloneLocalSet(allocator, locals);
    defer then_active_locals.deinit(allocator);
    try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, &then_active_locals, ctx, true);
    try emitBody(allocator, tokens, open_brace + 1, close_brace, body_start, &then_active_locals, &then_return_cleanup_locals, &then_control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, &then_defer, return_label, self_tail_tco, out);
    if (bodyCanReachEnd(tokens, open_brace + 1, close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &then_locals, ctx, out);
    }
    if (else_if_start) |nested_if| {
        try out.appendSlice(allocator, "    else\n");
        var else_if_active_locals = try cloneLocalSet(allocator, locals);
        defer else_if_active_locals.deinit(allocator);
        try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, &else_if_active_locals, ctx, false);
        if (!try emitIfBlock(allocator, tokens, nested_if, end_idx, body_start, &else_if_active_locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, self_tail_tco, out)) return false;
    } else if (else_open) |open_else| {
        const close_else = else_close orelse return false;
        try out.appendSlice(allocator, "    else\n");
        var else_locals = LocalSet{};
        defer else_locals.deinit(allocator);
        try collectDirectBodyLocals(allocator, tokens, open_else + 1, close_else, ctx, &else_locals);
        const else_defer = DeferContext{
            .parent = parent_defer_ptr,
            .start_idx = open_else + 1,
            .end_idx = close_else,
            .registered_end_idx = close_else,
        };
        var else_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &else_locals);
        defer else_return_cleanup_locals.deinit(allocator);
        var else_control_cleanup_locals = try mergeReturnCleanupLocals(allocator, control_cleanup_locals, &else_locals);
        defer else_control_cleanup_locals.deinit(allocator);
        var else_active_locals = try cloneLocalSet(allocator, locals);
        defer else_active_locals.deinit(allocator);
        try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, &else_active_locals, ctx, false);
        try emitBody(allocator, tokens, open_else + 1, close_else, body_start, &else_active_locals, &else_return_cleanup_locals, &else_control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, &else_defer, return_label, self_tail_tco, out);
        if (bodyCanReachEnd(tokens, open_else + 1, close_else)) {
            try emitBlockReleaseManagedLocals(allocator, &else_locals, ctx, out);
        }
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}

pub fn isCodegenScalarOrErrorType(tokens: []const lexer.Token, ctx: CodegenContext, ty: []const u8) bool {
    return isCodegenScalarType(ctx, ty) or isErrorLikeType(tokens, ty);
}
