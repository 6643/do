//! Struct bind / field / literal emit.
//! Storage / tuple emit and pack helpers.

const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const IsComparisonNarrowing = gen_types.IsComparisonNarrowing;
const NilComparisonNarrowing = gen_types.NilComparisonNarrowing;
const TypedStructBinding = gen_types.TypedStructBinding;
const gen_collect = @import("gen_collect.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const gen_hooks = @import("gen_hooks.zig");
const gen_ownership = @import("gen_ownership.zig");
const findTopLevelGuardLoopControl = gen_ownership.findTopLevelGuardLoopControl;
const labelForLoopStart = gen_ownership.labelForLoopStart;
const findValueEnumDeclLineByName = gen_import.findValueEnumDeclLineByName;
const findValueEnumDeclLineByBranch = gen_import.findValueEnumDeclLineByBranch;
const simpleTypeName = gen_collect.simpleTypeName;
const isTopLevelCommaAny = gen_collect.isTopLevelCommaAny;
const isReturnArrowAt = gen_collect.isReturnArrowAt;
const gen_union = @import("codegen_union_layout.zig");
const gen_host = @import("gen_host.zig");
const gen_wasi = @import("codegen_wasi_registry.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");

const tokEq = gen_util.tokEq;
const findMatching = gen_util.findMatching;
const findMatchingInRange = gen_util.findMatchingInRange;
const findLineEnd = gen_util.findLineEnd;
const findLineStart = gen_util.findLineStart;
const isLineStart = gen_util.isLineStart;
const findTopLevelToken = gen_util.findTopLevelToken;
const findArgEnd = gen_util.findArgEnd;
const trimParens = gen_util.trimParens;
const publicDeclName = gen_util.publicDeclName;
const appendFmt = gen_util.appendFmt;
const Range = gen_util.Range;
const alignUp = gen_util.alignUp;
const compactTokenText = gen_util.compactTokenText;
const stringTokenBody = gen_util.stringTokenBody;
const stringLiteralArgLexeme = gen_util.stringLiteralArgLexeme;
const isStringLiteralArg = gen_util.isStringLiteralArg;
const decodeQuotedStringToken = gen_util.decodeQuotedStringToken;
const findToken = gen_util.findToken;
const findTopLevelBlockOpen = gen_util.findTopLevelBlockOpen;
const findStmtEnd = gen_util.findStmtEnd;
const findTypeArgEnd = gen_util.findTypeArgEnd;
const moduleTokensEqual = gen_util.moduleTokensEqual;
const moduleScopedSymbolName = gen_util.moduleScopedSymbolName;
const appendMangledTypeName = gen_util.appendMangledTypeName;
const isUserFuncDeclStart = gen_util.isUserFuncDeclStart;
const isPublicTypeName = gen_util.isPublicTypeName;
const isErrorTypeName = gen_util.isErrorTypeName;
const isBaseIntTypeName = gen_util.isBaseIntTypeName;
const isCoreWasmScalar = gen_util.isCoreWasmScalar;
const isCoreIntegerScalar = gen_util.isCoreIntegerScalar;
const isCoreFloatScalar = gen_util.isCoreFloatScalar;
const isNumericCoreFuncName = gen_util.isNumericCoreFuncName;
const isBitwiseCoreFuncName = gen_util.isBitwiseCoreFuncName;
const isCountBitsCoreFuncName = gen_util.isCountBitsCoreFuncName;
const isNumericUnarySelectCoreFuncName = gen_util.isNumericUnarySelectCoreFuncName;
const isNumericBinarySelectCoreFuncName = gen_util.isNumericBinarySelectCoreFuncName;
const isFloatUnaryCoreFuncName = gen_util.isFloatUnaryCoreFuncName;
const isFloatBinaryCoreFuncName = gen_util.isFloatBinaryCoreFuncName;
const isBoolSpecialFuncName = gen_util.isBoolSpecialFuncName;
const isComparisonCoreFuncName = gen_util.isComparisonCoreFuncName;
const isMemoryLoadName = gen_util.isMemoryLoadName;
const isCoreWasmCallName = gen_util.isCoreWasmCallName;
const tokenTextEqualsCompact = gen_util.tokenTextEqualsCompact;
const findTopLevelTypeSeparator = gen_util.findTopLevelTypeSeparator;
const findTopLevelTypeSeparatorFrom = gen_util.findTopLevelTypeSeparatorFrom;
const hasString = gen_util.hasString;

const LocalSet = gen_types.LocalSet;
const Local = gen_types.Local;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const StructDecl = gen_types.StructDecl;
const StructField = gen_types.StructField;
const StructLayout = gen_types.StructLayout;
const StructLocal = gen_types.StructLocal;
const StorageLocal = gen_types.StorageLocal;
const UnionLocal = gen_types.UnionLocal;
const FuncDecl = gen_types.FuncDecl;
const FuncParam = gen_types.FuncParam;
const FuncResultItem = gen_types.FuncResultItem;
const HostImport = gen_types.HostImport;
const DeferContext = gen_types.DeferContext;
const CallLastUseMoveContext = gen_types.CallLastUseMoveContext;
const LastUseManagedMoveSource = gen_types.LastUseManagedMoveSource;
const LoopControl = gen_types.LoopControl;
const FieldMetaLocal = gen_types.FieldMetaLocal;
const FieldReflectionLoopHeader = gen_types.FieldReflectionLoopHeader;
const FieldStaticValue = gen_types.FieldStaticValue;
const FieldReflectionIfParts = gen_types.FieldReflectionIfParts;
const GenericTypeBinding = gen_types.GenericTypeBinding;
const PayloadEnumDecl = gen_types.PayloadEnumDecl;
const ValueEnumDecl = gen_types.ValueEnumDecl;
const CallbackBinding = gen_types.CallbackBinding;
const CallbackCallArg = gen_types.CallbackCallArg;
const FuncTypeShape = gen_types.FuncTypeShape;
const LambdaExprShape = gen_types.LambdaExprShape;
const NarrowedUnionLocal = gen_types.NarrowedUnionLocal;
const UnionStructPayload = gen_types.UnionStructPayload;
const ImportedAliasContext = gen_types.ImportedAliasContext;
const StringDataContext = gen_types.StringDataContext;
const ExprCallHead = gen_types.ExprCallHead;
const STORAGE_OVERWRITE_TMP_LOCAL = gen_types.STORAGE_OVERWRITE_TMP_LOCAL;
const STORAGE_WRITE_INDEX_TMP_LOCAL = gen_types.STORAGE_WRITE_INDEX_TMP_LOCAL;
const STORAGE_PUT_SOURCE_TMP_LOCAL = gen_types.STORAGE_PUT_SOURCE_TMP_LOCAL;
const STORAGE_WRITE_LEN_TMP_LOCAL = gen_types.STORAGE_WRITE_LEN_TMP_LOCAL;
const STORAGE_WRITE_SCAN_TMP_LOCAL = gen_types.STORAGE_WRITE_SCAN_TMP_LOCAL;
const STORAGE_WRITE_TARGET_TMP_LOCAL = gen_types.STORAGE_WRITE_TARGET_TMP_LOCAL;
const STORAGE_WRITE_NEXT_TMP_LOCAL = gen_types.STORAGE_WRITE_NEXT_TMP_LOCAL;
const TUPLE_PACK_BASE_TMP_LOCAL = gen_types.TUPLE_PACK_BASE_TMP_LOCAL;
const STRUCT_LITERAL_TMP_LOCAL = gen_types.STRUCT_LITERAL_TMP_LOCAL;
const STORAGE_PAYLOAD_HEADER_BYTES = gen_types.STORAGE_PAYLOAD_HEADER_BYTES;
const TYPE_ID_STORAGE_U8 = gen_types.TYPE_ID_STORAGE_U8;
const TYPE_ID_STORAGE_MANAGED = gen_types.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_FIRST_STRUCT = gen_types.TYPE_ID_FIRST_STRUCT;
const findLocalType = gen_types.findLocalType;
const findLocalOrigin = gen_types.findLocalOrigin;
const findStorageLocal = gen_types.findStorageLocal;
const findStructLocal = gen_types.findStructLocal;
const findUnionLocal = gen_types.findUnionLocal;
const hasLocal = gen_types.hasLocal;
const isCompilerLocalName = gen_types.isCompilerLocalName;
const storageTypeNameForElem = gen_types.storageTypeNameForElem;
const storageTypeNameForElemOwned = gen_types.storageTypeNameForElemOwned;
const localNameMatches = gen_types.localNameMatches;
const unionPayloadLocalName = gen_types.unionPayloadLocalName;
const unionTagLocalName = gen_types.unionTagLocalName;

const UnionLayout = gen_union.UnionLayout;
const UnionBranch = gen_union.UnionBranch;
const freeUnionLayout = gen_union.freeUnionLayout;
const cloneUnionLayout = gen_union.cloneUnionLayout;
const unionLayoutsEqual = gen_union.unionLayoutsEqual;
const unionBranchIsStatusI32 = gen_union.unionBranchIsStatusI32;

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

const WasiHostImport = gen_wasi.WasiHostImport;









const gen_storage = @import("gen_storage.zig");
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
fn emitFieldReflectionStaticIf(
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
    const parts = fieldReflectionIfParts(tokens, i, stmt_end) orelse return false;
    const condition = fieldStaticBoolExpr(tokens, parts.cond_start, parts.cond_end, locals, ctx) orelse return false;
    if (segment_start.* < i) {
        try gen_hooks.emitBody(allocator, tokens, segment_start.*, i, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, null, out);
    }
    try emitFieldReflectionStaticBranch(
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

fn collectFieldReflectionStaticIf(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    i: usize,
    stmt_end: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!bool {
    const parts = fieldReflectionIfParts(tokens, i, stmt_end) orelse return false;
    const condition = fieldStaticBoolExpr(tokens, parts.cond_start, parts.cond_end, out, ctx) orelse return false;
    try collectFieldReflectionStaticBranch(allocator, tokens, parts, condition, stmt_end, ctx, out);
    return true;
}

fn emitFieldReflectionStaticBranch(
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
        try emitFieldReflectionBody(allocator, tokens, parts.then_start, parts.then_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
        return;
    }
    if (parts.else_if_start) |nested_if| {
        try emitFieldReflectionBody(allocator, tokens, nested_if, stmt_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
        return;
    }
    if (parts.else_start) |else_start| {
        try emitFieldReflectionBody(allocator, tokens, else_start, parts.else_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
}

fn collectFieldReflectionStaticBranch(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    parts: FieldReflectionIfParts,
    condition: bool,
    stmt_end: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!void {
    if (condition) {
        try collectFieldReflectionBodyLocals(allocator, tokens, parts.then_start, parts.then_end, ctx, out);
        return;
    }
    if (parts.else_if_start) |nested_if| {
        try collectFieldReflectionBodyLocals(allocator, tokens, nested_if, stmt_end, ctx, out);
        return;
    }
    if (parts.else_start) |else_start| {
        try collectFieldReflectionBodyLocals(allocator, tokens, else_start, parts.else_end, ctx, out);
    }
}

pub fn emitFieldReflectionBody(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
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
    out: *std.ArrayList(u8)) CodegenError!void {
    var i = start_idx;
    var segment_start = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (try emitFieldReflectionStaticIf(
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
        try gen_hooks.emitBody(allocator, tokens, segment_start, end_idx, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, null, out);
    }
}


pub fn emitFieldReflectionLoopBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    header: FieldReflectionLoopHeader,
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
    out: *std.ArrayList(u8)) CodegenError!bool {
    const source_label = labelForLoopStart(tokens, header.loop_idx);
    const break_label = try std.fmt.allocPrint(allocator, "__field_break_{d}", .{header.loop_idx});
    defer allocator.free(break_label);

    try appendFmt(allocator, out, "    ;; field-reflect-loop type={s}\n", .{header.decl.name});
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!fieldVisibleFromTokens(field, header.decl, tokens)) continue;
        const prefix = try fieldReflectionLocalNamePrefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        const continue_label = try std.fmt.allocPrint(allocator, "__field_continue_{d}_{d}", .{ header.loop_idx, visible_index });
        defer allocator.free(continue_label);
        var field_locals = try borrowedFieldMetaLocalSet(allocator, locals, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collectFieldReflectionBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &field_locals);
        var field_cleanup_locals = try fieldReflectionScopedCleanupLocalSet(allocator, &field_locals, prefix);
        defer field_cleanup_locals.deinit(allocator);
        const field_loop = LoopControl{
            .parent = if (loop_ctx) |*control| control else null,
            .source_label = source_label,
            .break_label = break_label,
            .continue_label = continue_label,
            .cleanup_locals = &field_cleanup_locals,
            .defer_ctx = defer_ctx orelse return error.NoMatchingCall,
        };
        try appendFmt(allocator, out, "    block ${s}\n", .{continue_label});
        var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &field_cleanup_locals);
        defer active_return_cleanup_locals.deinit(allocator);
        var active_control_cleanup_locals = try mergeReturnCleanupLocals(allocator, control_cleanup_locals, &field_cleanup_locals);
        defer active_control_cleanup_locals.deinit(allocator);
        try emitFieldReflectionBody(allocator, tokens, header.open_brace + 1, header.close_brace, body_start, &field_locals, &active_return_cleanup_locals, &active_control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, field_loop, defer_ctx, return_label, out);
        if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
            try emitBlockReleaseManagedLocals(allocator, &field_cleanup_locals, ctx, out);
        }
        try out.appendSlice(allocator, "    end\n");
        visible_index += 1;
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}


pub fn emitManagedStructFieldSet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    target_name: []const u8,
    field_name: []const u8,
    field_offset: usize,
    field_ty: []const u8,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!void {
    const move_ctx = if (allow_last_use_move) CallLastUseMoveContext{
        .stmt_end = value_end,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    } else null;
    if (!try gen_hooks.emitExprWithMoveContext(allocator, tokens, value_start, value_end, locals, ctx, field_ty, if (move_ctx) |*ctx_info| ctx_info else null, out)) return error.NoMatchingCall;
    const move_source = if (allow_last_use_move)
        directManagedLastUseMoveSource(tokens, value_start, value_end, body_end, target_name, locals, ctx, defer_ctx)
    else
        null;
    if (move_source == null and isDirectManagedLocalExpr(tokens, value_start, value_end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});

    const struct_local = findStructLocal(locals.struct_locals.items, target_name) orelse return error.NoMatchingCall;
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return error.NoMatchingCall;
    const layout = findStructLayout(ctx.struct_layouts, struct_local.ty) orelse return error.NoMatchingCall;

    try appendFmt(allocator, out, "    local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      ;; arc-managed-struct-reuse {s}.{s}\n", .{ target_name, field_name });
    try appendFmt(allocator, out, "      ;; arc-overwrite-release {s}.{s}\n", .{ target_name, field_name });
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    try out.appendSlice(allocator, "      i32.ne\n");
    try out.appendSlice(allocator, "      if\n");
    try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    try out.appendSlice(allocator, "        call $__arc_dec\n");
    try out.appendSlice(allocator, "      end\n");
    try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendStoreForPayloadType(allocator, out, field_ty);
    try appendFmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "    else\n");
    try appendFmt(allocator, out, "      ;; arc-managed-struct-clone-set {s}.{s}\n", .{ target_name, field_name });
    try emitManagedStructCloneWithFieldSet(allocator, target_name, field_name, decl, struct_local.ty, layout, out);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
    if (move_source) |source| {
        try appendFmt(allocator, out, "    ;; field-set-move {s}\n", .{source.source_name});
        try emitZeroValueForType(allocator, ctx, out, field_ty);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
}


pub fn emitStructBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    decl: StructDecl,
    out: *std.ArrayList(u8)
) !void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const source_name = tokens[start_idx].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, source_name);
    const target_name = if (struct_local) |local| local.name else resolvedLocalName(locals.locals.items, source_name);
    const struct_ty = if (struct_local) |local|
        local.ty
    else if (try typedStructBinding(allocator, tokens, start_idx, end_idx, ctx, &owned_types)) |binding|
        binding.ty
    else if (inferredStructBinding(tokens, start_idx, end_idx, locals, ctx)) |binding|
        binding.ty
    else
        decl.name;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    if (findStructLayout(ctx.struct_layouts, struct_ty) != null and !isStructLiteralRhs(tokens, eq_idx + 1, end_idx)) {
        if (try emitManagedStructSetBinding(allocator, tokens, eq_idx + 1, end_idx, target_name, locals, ctx, decl, struct_ty, &owned_types, out)) {
            return;
        }
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
            struct_ty,
            out,
        );
        if (!emitted_move_call and !try gen_hooks.emitExpr(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, struct_ty, out)) return error.NoMatchingCall;
        if (!emitted_move_call and isDirectManagedLocalExpr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }
    if (findStructLayout(ctx.struct_layouts, struct_ty) == null) {
        if (try emitWasiRecordStructBinding(allocator, tokens, start_idx, end_idx, locals, ctx, decl, out)) {
            return;
        }
        if (try emitUnmanagedStructCallBinding(
            allocator,
            tokens,
            start_idx,
            end_idx,
            body_end,
            allow_last_use_move,
            locals,
            defer_ctx,
            ctx,
            decl,
            struct_ty,
            out,
        )) {
            return;
        }
        if (!isStructLiteralRhs(tokens, eq_idx + 1, end_idx)) {
            if (!try gen_hooks.emitExpr(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, struct_ty, out)) return error.NoMatchingCall;
            var field_idx = decl.fields.len;
            while (field_idx > 0) {
                field_idx -= 1;
                try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
                    target_name,
                    publicDeclName(decl.fields[field_idx].name),
                });
            }
            return;
        }
    }
    const open_brace = structLiteralOpenRhs(tokens, eq_idx + 1, end_idx) orelse return error.NoMatchingCall;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return error.NoMatchingCall;
    if (close_brace + 1 != end_idx) return error.NoMatchingCall;

    if (findStructLayout(ctx.struct_layouts, struct_ty)) |layout| {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
        try out.appendSlice(allocator, "    call $__arc_alloc\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        try emitManagedStructFields(allocator, tokens, open_brace + 1, close_brace, target_name, locals, ctx, decl, struct_ty, layout, &owned_types, out);
        return;
    }

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = findStructLiteralField(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        try emitStructFieldValue(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, false, out);
        try emitStructFieldLocalSet(allocator, tokens, target_name, field_name, field_ty, locals, ctx, out);
    }
}


pub fn emitStructFieldValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    field_ty: []const u8,
    copy_managed: bool,
    out: *std.ArrayList(u8)
) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        if (!try gen_hooks.emitUnionValue(allocator, tokens, start_idx, end_idx, locals, ctx, layout, copy_managed, null, out)) {
            return error.NoMatchingCall;
        }
        return;
    }
    if (!try gen_hooks.emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, field_ty, out)) {
        return error.NoMatchingCall;
    }
}


pub fn emitUnmanagedStructCallBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    decl: StructDecl,
    struct_ty: []const u8,
    out: *std.ArrayList(u8)) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const result_struct = func.result_struct orelse return false;
    if (!std.mem.eql(u8, result_struct, struct_ty)) return false;
    if (func.results.len != decl.fields.len) return error.NoMatchingCall;
    for (decl.fields, 0..) |field, idx| {
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        if (!std.mem.eql(u8, field_ty, func.results[idx])) return error.NoMatchingCall;
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

    var i = decl.fields.len;
    while (i > 0) {
        i -= 1;
        const field = decl.fields[i];
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        try emitStructFieldLocalSet(allocator, tokens, tokens[start_idx].lexeme, publicDeclName(field.name), field_ty, locals, ctx, out);
    }
    return true;
}


pub fn emitUnmanagedStructErrorUnionReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    defer_ctx: ?*const DeferContext,
    out: *std.ArrayList(u8)
) !bool {
    const error_name = unmanagedStructErrorUnionResult(tokens, ctx, result_tys, result_struct) orelse return false;
    const struct_name = result_struct.?;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (start_idx + 1 >= end_idx) return error.NoMatchingCall;

    const expr_start = start_idx + 1;
    const expr_end = end_idx;
    const range = trimParens(tokens, expr_start, expr_end);

    if (try emitUnmanagedStructErrorUnionFromCall(
        allocator,
        tokens,
        range,
        body_start,
        end_idx,
        locals,
        ctx,
        result_tys,
        defer_ctx,
        out,
    )) |ok| return ok;

    return emitUnmanagedStructErrorUnionFromIdent(
        allocator,
        tokens,
        range,
        locals,
        ctx,
        error_name,
        struct_name,
        decl,
        out,
    );
}

fn resultTypesMatch(result_tys: []const []const u8, func_results: []const []const u8) bool {
    if (func_results.len != result_tys.len) return false;
    for (result_tys, 0..) |result_ty, i| {
        if (!std.mem.eql(u8, result_ty, func_results[i])) return false;
    }
    return true;
}

/// Returns `null` when RHS is not a call (caller may try other shapes);
/// `true`/`false` when a call was handled or rejected.
fn emitUnmanagedStructErrorUnionFromCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range: Range,
    body_start: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    defer_ctx: ?*const DeferContext,
    out: *std.ArrayList(u8),
) !?bool {
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (!resultTypesMatch(result_tys, func.results)) return false;

    const move_ctx = CallLastUseMoveContext{
        .body_start = body_start,
        .stmt_end = end_idx,
        .body_end = end_idx,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    };
    return try gen_hooks.emitUserFuncCallWithMoveContext(
        allocator,
        tokens,
        call_head.args_start,
        call_head.args_end,
        locals,
        ctx,
        func,
        &move_ctx,
        out,
    );
}

fn emitUnmanagedStructErrorUnionFromIdent(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range: Range,
    locals: *const LocalSet,
    ctx: CodegenContext,
    error_name: []const u8,
    struct_name: []const u8,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) !bool {
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    const name = tokens[range.start].lexeme;

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (std.mem.eql(u8, struct_local.ty, struct_name) and findStructLayout(ctx.struct_layouts, struct_name) == null) {
            try emitStructFieldsFromLocal(allocator, tokens, struct_local, decl, locals, ctx, false, out);
            try out.appendSlice(allocator, "    i32.const 0\n");
            return true;
        }
    }

    const is_error_branch = errorEnumBranchValue(tokens, error_name, name) != null;
    const is_error_local = std.mem.eql(u8, findLocalType(locals.locals.items, name) orelse "", error_name);
    if (!is_error_branch and !is_error_local) return false;

    for (decl.fields) |field| {
        try emitZeroValueForType(allocator, ctx, out, field.ty);
    }
    if (!try gen_hooks.emitExpr(allocator, tokens, range.start, range.end, locals, ctx, error_name, out)) {
        return error.NoMatchingCall;
    }
    return true;
}


pub fn emitUserFuncArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    param_ty: []const u8,
    copy_managed: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, param_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        return try gen_hooks.emitUnionValue(allocator, tokens, arg_start, arg_end, locals, ctx, layout, copy_managed, null, out);
    }
    if (isTupleTypeName(param_ty)) {
        if (try emitTupleExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out)) {
            return true;
        }
    }
    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        if (findStructLocal(locals.struct_locals.items, tokens[range.start].lexeme)) |struct_local| {
            if (std.mem.eql(u8, struct_local.ty, param_ty) and findStructLayout(ctx.struct_layouts, param_ty) == null) {
                const decl = findStructDecl(ctx.structs, param_ty) orelse return false;
                try emitStructFieldsFromLocal(allocator, tokens, struct_local, decl, locals, ctx, false, out);
                return true;
            }
        }
        if (try gen_hooks.emitUnionStructPayloadForType(allocator, tokens, tokens[range.start].lexeme, param_ty, locals, ctx, false, out)) {
            return true;
        }
    }
    return try gen_hooks.emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out);
}


pub fn emitStructFieldMetaSetAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)
) !bool {
    if (start_idx + 6 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;

    var name_idx = start_idx + 2;
    if (tokEq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= end_idx) return false;
    }
    if (!std.mem.eql(u8, tokens[name_idx].lexeme, "field_set")) return false;
    if (name_idx + 1 >= end_idx or !tokEq(tokens[name_idx + 1], "(")) return false;

    const open_paren = name_idx + 1;
    const args_start = open_paren + 1;
    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", end_idx) catch return false;
    if (close_paren + 1 != end_idx) return false;

    const first_end = findArgEnd(tokens, args_start, close_paren);
    if (first_end != args_start + 1 or !std.mem.eql(u8, tokens[args_start].lexeme, tokens[start_idx].lexeme)) return false;
    if (first_end >= close_paren or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, close_paren);
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return false;
    if (field_end >= close_paren or !tokEq(tokens[field_end], ",")) return false;

    const value_start = field_end + 1;
    const field = fieldFromMeta(ctx, meta) orelse return false;
    const field_name = publicDeclName(field.name);
    const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse field.ty;

    try appendFmt(allocator, out, "    ;; field-set name={s} field={s}\n", .{
        tokens[start_idx].lexeme,
        field_name,
    });

    if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        if (isManagedStructField(layout, field_name)) {
            try emitManagedStructFieldSet(
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
        try appendManagedStructFieldPtr(allocator, out, tokens[start_idx].lexeme, field_offset);
        if (!try gen_hooks.emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try appendStoreForPayloadType(allocator, out, field_ty);
        return true;
    }

    if (!try gen_hooks.emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}


pub fn emitStructLiteralExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: []const u8,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    const decl = findStructDecl(ctx.structs, expected_ty) orelse return false;
    const open_brace = structLiteralOpenRhs(tokens, start_idx, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    if (findStructLayout(ctx.struct_layouts, expected_ty)) |layout| {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
        try out.appendSlice(allocator, "    call $__arc_alloc\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STRUCT_LITERAL_TMP_LOCAL});
        try emitManagedStructFields(allocator, tokens, open_brace + 1, close_brace, STRUCT_LITERAL_TMP_LOCAL, locals, ctx, decl, expected_ty, layout, &owned_types, out);
        try appendFmt(allocator, out, "    local.get ${s}\n", .{STRUCT_LITERAL_TMP_LOCAL});
        return true;
    }

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = findStructLiteralField(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substituteStructFieldType(allocator, decl, expected_ty, field.ty, &owned_types);
        try emitStructFieldValue(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, false, out);
    }
    return true;
}


pub fn emitStructSetAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)
) !bool {
    if (start_idx + 6 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;

    var name_idx = start_idx + 2;
    if (tokEq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= end_idx) return false;
    }
    if (!std.mem.eql(u8, tokens[name_idx].lexeme, "set")) return false;
    if (name_idx + 1 >= end_idx or !tokEq(tokens[name_idx + 1], "(")) return false;

    const open_paren = name_idx + 1;
    const args_start = open_paren + 1;
    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", end_idx) catch return false;
    if (close_paren + 1 != end_idx) return false;

    const first_end = findArgEnd(tokens, args_start, close_paren);
    if (first_end != args_start + 1 or !std.mem.eql(u8, tokens[args_start].lexeme, tokens[start_idx].lexeme)) return false;
    if (first_end >= close_paren or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, close_paren);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (field_end >= close_paren or !tokEq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const field_name = publicDeclName(tokens[field_start].lexeme);
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
    const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
        findStructFieldType(decl, field_name) orelse return false;

    if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        try appendFmt(allocator, out, "    ;; arc-managed-struct-set name={s} field={s} offset={d}\n", .{
            tokens[start_idx].lexeme,
            field_name,
            field_offset,
        });
        if (isManagedStructField(layout, field_name)) {
            try emitManagedStructFieldSet(
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
        try appendManagedStructFieldPtr(allocator, out, tokens[start_idx].lexeme, field_offset);
        if (!try gen_hooks.emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try appendStoreForPayloadType(allocator, out, field_ty);
        return true;
    }

    if (!try gen_hooks.emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}


pub fn fieldStaticValuesEqual(left: FieldStaticValue, right: FieldStaticValue) bool {
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



pub fn fieldReflectionLocalVisible(name: []const u8, scoped_prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "__field_")) return true;
    return std.mem.startsWith(u8, name, scoped_prefix);
}



pub fn appendUnionPayloadLocalGet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8,
    idx: usize) !void {
    try appendFmt(allocator, out, "    local.get ${s}.__union_payload_{d}\n", .{ base, idx });
}



pub fn resolvedLocalName(locals: []const Local, name: []const u8) []const u8 {
    return findLocalName(locals, name) orelse name;
}



pub fn appendUnionTagLocalGet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8) !void {
    try appendFmt(allocator, out, "    local.get ${s}.__union_tag\n", .{base});
}



pub fn appendUnionTagLocalSet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8) !void {
    try appendFmt(allocator, out, "    local.set ${s}.__union_tag\n", .{base});
}



pub fn isManagedStructField(layout: StructLayout, field_name: []const u8) bool {
    for (layout.managed_fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) return true;
    }
    return false;
}



pub fn structLocalSourceName(local: StructLocal) []const u8 {
    return local.source_name orelse local.name;
}



fn typeArgsCloseIdx(tokens: []const lexer.Token, open_angle: usize, end_idx: usize) ?usize {
    var depth: usize = 0;
    var j = open_angle;
    while (j < end_idx) : (j += 1) {
        if (tokEq(tokens[j], "<")) {
            depth += 1;
            continue;
        }
        if (!tokEq(tokens[j], ">")) continue;
        if (depth == 0) return null;
        depth -= 1;
        if (depth == 0) return j;
    }
    return null;
}

pub fn stmtContainsStructLiteralExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and tokEq(tokens[i + 1], "{")) return true;
        if (tokens[i].kind == .ident and tokEq(tokens[i + 1], "<")) {
            const close = typeArgsCloseIdx(tokens, i + 1, end_idx) orelse continue;
            if (close + 1 < end_idx and tokEq(tokens[close + 1], "{")) return true;
        }
        if (tokEq(tokens[i], ".") and tokEq(tokens[i + 1], "{")) return true;
    }
    return false;
}






pub fn fieldReflectionLocalNamePrefix(
    allocator: std.mem.Allocator,
    header: FieldReflectionLoopHeader,
    visible_index: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "__field_{d}_{d}_", .{ header.open_brace, visible_index });
}






pub fn emitUnmanagedStructReturnLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    out: *std.ArrayList(u8)) !bool {
    const struct_name = result_struct orelse return false;
    if (isTupleTypeName(struct_name)) return false;
    if (start_idx + 2 != end_idx) return false;
    if (tokens[start_idx + 1].kind != .ident) return false;
    const local_name = tokens[start_idx + 1].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, local_name) orelse return false;
    if (!std.mem.eql(u8, struct_local.ty, struct_name)) return false;
    if (findStructLayout(ctx.struct_layouts, struct_name) != null) return false;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (decl.fields.len != result_tys.len) return error.NoMatchingCall;

    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return error.NoMatchingCall;
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            local_name,
            publicDeclName(field.name),
        });
    }
    return true;
}






pub fn emitStructFieldLocalGet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    base: []const u8,
    field_name: []const u8,
    field_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8)) CodegenError!void {
    _ = tokens;
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, field_name });
    defer allocator.free(union_local_name);
    if (findUnionLocal(locals.union_locals.items, union_local_name)) |union_local| {
        for (union_local.layout.payload_tys, 0..) |payload_ty, idx| {
            try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
            if (copy_managed and isManagedLocalType(payload_ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
        }
        try appendUnionTagLocalGet(allocator, out, union_local.name);
        return;
    }
    try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{ base, field_name });
    if (copy_managed and isManagedLocalType(field_ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
}




pub fn emitStructFieldLocalSet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    base: []const u8,
    field_name: []const u8,
    field_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!void {
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, field_name });
    defer allocator.free(union_local_name);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        const union_local = findUnionLocal(locals.union_locals.items, union_local_name) orelse return error.NoMatchingCall;
        if (!unionLayoutsEqual(union_local.layout, layout)) return error.NoMatchingCall;
        var idx = union_local.layout.payload_tys.len + 1;
        while (idx > 0) {
            idx -= 1;
            if (idx == union_local.layout.payload_tys.len) {
                try appendUnionTagLocalSet(allocator, out, union_local.name);
            } else {
                try appendUnionPayloadLocalSet(allocator, out, union_local.name, idx);
            }
        }
        return;
    }
    if (isTupleTypeName(field_ty)) {
        return try emitTupleLocalSet(allocator, union_local_name, field_ty, ctx, out);
    }
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{ base, field_name });
}




pub fn emitStructFieldsFromLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    struct_local: StructLocal,
    decl: StructDecl,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8)) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    for (decl.fields) |field| {
        const field_ty = try substituteStructFieldType(allocator, decl, struct_local.ty, field.ty, &owned_types);
        try emitStructFieldLocalGet(allocator, tokens, struct_local.name, publicDeclName(field.name), field_ty, locals, ctx, copy_managed, out);
    }
}








pub fn emitManagedStructSetBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    target_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    struct_ty: []const u8,
    owned_types: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8)
) CodegenError!bool {
    const layout = findStructLayout(ctx.struct_layouts, struct_ty) orelse return false;
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "set")) return false;

    const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
    if (first_end != call_head.args_start + 1 or tokens[call_head.args_start].kind != .ident) return false;
    if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return false;
    const source_local = findStructLocal(locals.struct_locals.items, tokens[call_head.args_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, source_local.ty, struct_ty)) return false;

    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, call_head.args_end);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (field_end >= call_head.args_end or !tokEq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const value_end = findArgEnd(tokens, value_start, call_head.args_end);
    if (value_end != call_head.args_end) return false;
    const target_field = publicDeclName(tokens[field_start].lexeme);

    try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, owned_types);
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
        if (std.mem.eql(u8, field_name, target_field)) {
            if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            if (isManagedStructField(layout, field_name) and isDirectManagedLocalExpr(tokens, value_start, value_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendStoreForPayloadType(allocator, out, field_ty);
            continue;
        }

        try appendManagedStructFieldPtr(allocator, out, source_local.name, field_offset);
        try appendLoadForPayloadType(allocator, out, field_ty);
        if (isManagedStructField(layout, field_name)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }
    return true;
}












pub fn emitManagedStructFields(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    local_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    struct_ty: []const u8,
    layout: StructLayout,
    owned_types: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8)
) !void {
    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = findStructLiteralField(tokens, start_idx, end_idx, field_name);
        const expr_tokens = if (literal_field) |_| tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return error.NoMatchingCall;
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, owned_types);

        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try out.appendSlice(allocator, "    call $__arc_payload\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        if (!try gen_hooks.emitExpr(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        if (isManagedStructField(layout, field_name) and isDirectManagedLocalExpr(expr_tokens, expr_start, expr_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }
}










pub fn emitManagedStructCloneWithFieldSet(
    allocator: std.mem.Allocator,
    target_name: []const u8,
    target_field_name: []const u8,
    decl: StructDecl,
    struct_ty: []const u8,
    layout: StructLayout,
    out: *std.ArrayList(u8)) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    try appendFmt(allocator, out, "      i32.const {d}\n", .{layout.payload_bytes});
    try appendFmt(allocator, out, "      i32.const {d}\n", .{layout.type_id});
    try out.appendSlice(allocator, "      call $__arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return error.NoMatchingCall;

        try appendManagedStructFieldPtr(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL, field_offset);
        if (std.mem.eql(u8, field_name, target_field_name)) {
            try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try appendStoreForPayloadType(allocator, out, field_ty);
            continue;
        }

        try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
        try appendLoadForPayloadType(allocator, out, field_ty);
        if (isManagedStructField(layout, field_name)) {
            try out.appendSlice(allocator, "      call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }

    try appendFmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "      call $__arc_dec\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
}




pub fn appendManagedStructFieldPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_name: []const u8,
    field_offset: usize) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
    try out.appendSlice(allocator, "    call $__arc_payload\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
    try out.appendSlice(allocator, "    i32.add\n");
}








pub fn fieldReflectionIfParts(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?FieldReflectionIfParts {
    if (start_idx + 4 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "if")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    var parts = FieldReflectionIfParts{
        .cond_start = start_idx + 1,
        .cond_end = open_brace,
        .then_start = open_brace + 1,
        .then_end = close_brace,
    };
    if (close_brace + 1 == end_idx) return parts;
    if (close_brace + 1 >= end_idx or !tokEq(tokens[close_brace + 1], "else")) return null;
    if (close_brace + 2 >= end_idx) return null;
    if (tokEq(tokens[close_brace + 2], "if")) {
        parts.else_if_start = close_brace + 2;
        return parts;
    }
    if (!tokEq(tokens[close_brace + 2], "{")) return null;
    const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return null;
    if (close_else + 1 != end_idx) return null;
    parts.else_start = close_brace + 3;
    parts.else_end = close_else;
    return parts;
}




pub fn fieldStaticBoolExpr(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?bool {
    if (fieldStaticValue(tokens, start_idx, end_idx, locals, ctx)) |value| {
        return switch (value) {
            .bool => |b| b,
            else => null,
        };
    }

    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic and std.mem.eql(u8, call_name, "not")) {
        const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return null;
        return !(fieldStaticBoolExpr(tokens, call_head.args_start, arg_end, locals, ctx) orelse return null);
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "and") or std.mem.eql(u8, call_name, "or"))) {
        var arg_start = call_head.args_start;
        var saw_arg = false;
        while (arg_start < call_head.args_end) {
            const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
            const value = fieldStaticBoolExpr(tokens, arg_start, arg_end, locals, ctx) orelse return null;
            saw_arg = true;
            if (std.mem.eql(u8, call_name, "and") and !value) return false;
            if (std.mem.eql(u8, call_name, "or") and value) return true;
            arg_start = arg_end;
            if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (!saw_arg) return null;
        return std.mem.eql(u8, call_name, "and");
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne"))) {
        const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return null;
        const second_start = first_end + 1;
        const second_end = findArgEnd(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return null;
        const left = fieldStaticValue(tokens, call_head.args_start, first_end, locals, ctx) orelse return null;
        const right = fieldStaticValue(tokens, second_start, second_end, locals, ctx) orelse return null;
        const is_equal = fieldStaticValuesEqual(left, right);
        return if (std.mem.eql(u8, call_name, "eq")) is_equal else !is_equal;
    }
    return null;
}




pub fn fieldStaticValue(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?FieldStaticValue {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .number) return .{ .int = std.fmt.parseUnsigned(usize, tok.lexeme, 10) catch return null };
        if (tok.kind == .string) return .{ .text = stringTokenBody(tok.lexeme) orelse return null };
        if (tokEq(tok, "true")) return .{ .bool = true };
        if (tokEq(tok, "false")) return .{ .bool = false };
        return null;
    }

    const call_head = exprCallHead(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "field_name")) {
        const meta = singleFieldMetaArg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = fieldFromMeta(ctx, meta) orelse return null;
        return .{ .text = publicDeclName(field.name) };
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        const meta = singleFieldMetaArg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        return .{ .int = meta.visible_index };
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        const meta = singleFieldMetaArg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = fieldFromMeta(ctx, meta) orelse return null;
        return .{ .bool = field.default_start != null };
    }
    return null;
}






pub fn fieldVisibleFromTokens(field: StructField, decl: StructDecl, tokens: []const lexer.Token) bool {
    if (!isPrivateFieldName(field.name)) return true;
    return moduleTokensEqual(decl.tokens, tokens);
}




pub fn isPrivateFieldName(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}











pub fn typedStructBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8)) CodegenError!?TypedStructBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed_ty.next_idx != eq_idx) return null;
    const ty = try substituteGenericTypeOwned(allocator, parsed_ty.ty, ctx.type_bindings, owned_types);
    const decl = findStructDecl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
}




pub fn inferredStructBinding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?TypedStructBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const ty = inferExprType(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    const decl = findStructDecl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
}




pub fn emitManagedStructExprFieldGet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    field_start: usize,
    field_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (value_end == value_start + 1 and tokens[value_start].kind == .ident) return false;
    const struct_ty = inferExprType(tokens, value_start, value_end, locals, ctx) orelse return false;
    const layout = findStructLayout(ctx.struct_layouts, struct_ty) orelse return false;
    const decl = findStructDecl(ctx.structs, struct_ty) orelse return false;
    const field_name = publicDeclName(tokens[field_start].lexeme);
    const field = findStructField(decl, field_name) orelse return false;
    const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);

    if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, struct_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendManagedStructFieldPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    if (isManagedStructField(layout, field_name)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
    return true;
}




pub fn emitFieldReflectionIntrinsic(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    if (std.mem.eql(u8, call_name, "field_name")) {
        const meta = singleFieldMetaArg(tokens, start_idx, end_idx, locals) orelse return false;
        const field = fieldFromMeta(ctx, meta) orelse return false;
        try emitStorageU8RawStringValue(allocator, publicDeclName(field.name), STORAGE_OVERWRITE_TMP_LOCAL, ctx, out);
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        const meta = singleFieldMetaArg(tokens, start_idx, end_idx, locals) orelse return false;
        try appendFmt(allocator, out, "    i32.const {d}\n", .{meta.visible_index});
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        const meta = singleFieldMetaArg(tokens, start_idx, end_idx, locals) orelse return false;
        const field = fieldFromMeta(ctx, meta) orelse return false;
        try appendFmt(allocator, out, "    i32.const {d}\n", .{@intFromBool(field.default_start != null)});
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_get")) {
        return try emitFieldGetCall(allocator, tokens, start_idx, end_idx, locals, ctx, move_ctx, out);
    }
    return false;
}




pub fn emitFieldGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != end_idx) return false;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;

    const name = tokens[start_idx].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, name) orelse return false;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return false;
    const field = fieldFromMeta(ctx, meta) orelse return false;
    const field_name = publicDeclName(field.name);

    if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        const move_source = if (move_ctx) |ctx_info|
            try fieldGetLastUseMoveSource(allocator, tokens, start_idx, end_idx, struct_local, field.ty, ctx_info.*, locals, ctx)
        else
            null;
        try appendFmt(allocator, out, "    local.get ${s}\n", .{struct_local.name});
        try out.appendSlice(allocator, "    call $__arc_payload\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        try appendLoadForPayloadType(allocator, out, field.ty);
        if (isManagedStructField(layout, field_name) and move_source == null) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        if (move_source) |source| {
            try appendFmt(allocator, out, "    ;; field-get-move {s}.{s}\n", .{ source.source_name, field_name });
            try emitZeroValueForType(allocator, ctx, out, field.ty);
            try appendManagedStructFieldPtr(allocator, out, struct_local.name, field_offset);
            try appendStoreForPayloadType(allocator, out, field.ty);
        }
        return true;
    }

    if (try emitUnmanagedStructFieldGet(allocator, tokens, struct_local, field_name, field.ty, locals, ctx, out)) {
        return true;
    }
    try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}




pub fn emitUnmanagedStructFieldGet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    struct_local: StructLocal,
    field_name: []const u8,
    field_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const layout = (try parseTypeUnionLayoutFromName(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) orelse return false;
    defer freeUnionLayout(allocator, layout);
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ struct_local.name, field_name });
    defer allocator.free(union_local_name);
    const union_local = findUnionLocal(locals.union_locals.items, union_local_name) orelse return false;
    if (!unionLayoutsEqual(union_local.layout, layout)) return false;
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
        if (isManagedLocalType(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try appendUnionTagLocalGet(allocator, out, union_local.name);
    return true;
}




pub fn emitStructSetExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    expected_ty: ?[]const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (field_end >= end_idx or !tokEq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const value_end = findArgEnd(tokens, value_start, end_idx);
    if (value_end != end_idx) return false;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const struct_ty = expected_ty orelse struct_local.ty;
    if (!std.mem.eql(u8, struct_local.ty, struct_ty)) return false;
    if (findStructLayout(ctx.struct_layouts, struct_ty) != null) return false;

    const decl = findStructDecl(ctx.structs, struct_ty) orelse return false;
    const target_field = publicDeclName(tokens[field_start].lexeme);
    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
            findStructFieldType(decl, field_name) orelse return false;
        if (std.mem.eql(u8, field_name, target_field)) {
            if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            continue;
        }
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            struct_local.name,
            field_name,
        });
    }
    return true;
}










pub fn borrowedFieldMetaLocalSet(
    allocator: std.mem.Allocator,
    parent: *const LocalSet,
    meta: FieldMetaLocal,
    scoped_prefix: []const u8) !LocalSet {
    var out = LocalSet{};
    errdefer out.deinit(allocator);
    for (parent.locals.items) |local| {
        if (!fieldReflectionLocalVisible(local.name, scoped_prefix)) continue;
        try out.locals.append(allocator, local);
    }
    for (parent.struct_locals.items) |local| {
        if (!fieldReflectionLocalVisible(local.name, scoped_prefix)) continue;
        try out.struct_locals.append(allocator, local);
    }
    for (parent.storage_locals.items) |local| {
        if (!fieldReflectionLocalVisible(local.name, scoped_prefix)) continue;
        try out.storage_locals.append(allocator, local);
    }
    for (parent.union_locals.items) |union_local| {
        if (!fieldReflectionLocalVisible(union_local.name, scoped_prefix)) continue;
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



pub fn singleFieldMetaArg(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?FieldMetaLocal {
    const arg_end = findArgEnd(tokens, start_idx, end_idx);
    if (arg_end != end_idx) return null;
    const range = trimParens(tokens, start_idx, arg_end);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return findFieldMetaLocal(locals.field_meta_locals.items, tokens[range.start].lexeme);
}



pub fn fieldGetLastUseMoveSource(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    struct_local: StructLocal,
    field_ty: []const u8,
    move_ctx: CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext) CodegenError!?LastUseManagedMoveSource {
    if (!isManagedLocalType(field_ty, ctx)) return null;

    const body_start = move_ctx.body_start;
    const source_name = structLocalSourceName(struct_local);
    const decl_end = (try freshStructLiteralBindingStmtEnd(
        allocator,
        tokens,
        body_start,
        start_idx,
        source_name,
        struct_local.ty,
        locals,
        ctx,
    )) orelse return null;
    const fresh_source_gap = tokenRangeUsesIdent(tokens, decl_end, start_idx, source_name);
    const after_expr_use = tokenRangeUsesIdent(tokens, end_idx, move_ctx.stmt_end, source_name);
    const body_rest_use = tokenRangeUsesIdent(tokens, move_ctx.stmt_end, move_ctx.body_end, source_name);
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
            .defer_visible = hasRegisteredDeferStmt(tokens, move_ctx.defer_ctx),
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




pub fn unmanagedStructErrorUnionResult(
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
) ?[]const u8 {
    const struct_name = result_struct orelse return null;
    if (findStructLayout(ctx.struct_layouts, struct_name) != null) return null;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return null;
    if (result_tys.len != decl.fields.len + 1) return null;
    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return null;
    }
    const error_name = result_tys[decl.fields.len];
    if (!isErrorLikeType(tokens, error_name)) return null;
    return error_name;
}



pub fn freshStructLiteralBindingStmtEnd(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    body_start: usize,
    expr_start: usize,
    source_name: []const u8,
    struct_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext) CodegenError!?usize {
    var i = body_start;
    while (i < expr_start) {
        const stmt_end = findStmtEnd(tokens, i, expr_start);
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, source_name)) {
            const eq_idx = findTopLevelToken(tokens, i + 1, stmt_end, "=") orelse return null;
            if (!isStructLiteralRhs(tokens, eq_idx + 1, stmt_end)) return null;

            var owned_types = std.ArrayList([]const u8).empty;
            defer {
                for (owned_types.items) |owned| allocator.free(owned);
                owned_types.deinit(allocator);
            }

            if (try typedStructBinding(allocator, tokens, i, stmt_end, ctx, &owned_types)) |binding| {
                if (std.mem.eql(u8, binding.ty, struct_ty)) return stmt_end;
                return null;
            }
            if (inferredStructBinding(tokens, i, stmt_end, locals, ctx)) |binding| {
                if (std.mem.eql(u8, binding.ty, struct_ty)) return stmt_end;
            }
            return null;
        }
        i = stmt_end;
    }
    return null;
}


// re-export gen_ownership
pub const emitReleaseManagedLocals = gen_ownership.emitReleaseManagedLocals;
pub const emitReleaseManagedLocalsExcept = gen_ownership.emitReleaseManagedLocalsExcept;
pub const emitReleaseManagedLocalsExceptMany = gen_ownership.emitReleaseManagedLocalsExceptMany;
pub const emitFallthroughReleaseManagedLocals = gen_ownership.emitFallthroughReleaseManagedLocals;
pub const emitBlockReleaseManagedLocals = gen_ownership.emitBlockReleaseManagedLocals;
pub const hasManagedLocals = gen_ownership.hasManagedLocals;
pub const managedLocalKindForType = gen_ownership.managedLocalKindForType;
pub const collectManagedOwnershipLocals = gen_ownership.collectManagedOwnershipLocals;
pub const buildReturnOwnershipPlan = gen_ownership.buildReturnOwnershipPlan;
pub const buildGuardReturnOwnershipPlan = gen_ownership.buildGuardReturnOwnershipPlan;
pub const buildFallthroughOwnershipPlan = gen_ownership.buildFallthroughOwnershipPlan;
pub const buildBlockOwnershipPlan = gen_ownership.buildBlockOwnershipPlan;
pub const emitOwnershipReleasePlan = gen_ownership.emitOwnershipReleasePlan;
pub const bodyEndsWithPlainReturn = gen_ownership.bodyEndsWithPlainReturn;
pub const bodyCanReachEnd = gen_ownership.bodyCanReachEnd;
pub const stmtCanReachEnd = gen_ownership.stmtCanReachEnd;
pub const ifStmtCanReachEnd = gen_ownership.ifStmtCanReachEnd;
pub const loopStmtCanReachEnd = gen_ownership.loopStmtCanReachEnd;






pub fn emitZeroValueForType(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    ty: []const u8) !void {
    try appendFmt(allocator, out, "    {s}.const 0\n", .{codegenWasmType(ctx, ty)});
}





pub fn collectFieldReflectionBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet) CodegenError!void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (try collectFieldReflectionStaticIf(allocator, tokens, i, stmt_end, ctx, out)) {
            i = stmt_end;
            continue;
        }
        try gen_hooks.collectBodyLocals(allocator, tokens, i, stmt_end, ctx, out);
        try applyCollectGuardReturnNarrowing(allocator, tokens, i, stmt_end, out, ctx);
        try applyGuardLoopControlNarrowing(allocator, tokens, i, stmt_end, out, ctx);
        i = stmt_end;
    }
}


pub fn appendUnionPayloadLocalSet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8,
    idx: usize) !void {
    try appendFmt(allocator, out, "    local.set ${s}.__union_payload_{d}\n", .{ base, idx });
}




pub fn applyGuardReturnNilNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = nilComparisonNarrowing(tokens, start_idx + 1, return_idx, locals) orelse return;
    if (narrowing.non_nil_when_true) return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
}


pub fn applyGuardReturnIsNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = try isComparisonNarrowing(allocator, tokens, start_idx + 1, return_idx, locals, ctx) orelse return;
    const payload_ty = unionLocalSingleRemainingPayloadType(narrowing.union_local, narrowing.payload_ty) orelse return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
}


pub fn applyGuardLoopControlNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return;

    if (nilComparisonNarrowing(tokens, start_idx + 1, control_idx, locals)) |narrowing| {
        if (!narrowing.non_nil_when_true) {
            try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
        }
    }

    if (try isComparisonNarrowing(allocator, tokens, start_idx + 1, control_idx, locals, ctx)) |narrowing| {
        const payload_ty = unionLocalSingleRemainingPayloadType(narrowing.union_local, narrowing.payload_ty) orelse return;
        try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
    }
}


pub fn nilComparisonNarrowing(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?NilComparisonNarrowing {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) return null;

    const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
    if (first_end == call_head.args_start or first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, call_head.args_end);
    if (second_end != call_head.args_end) return null;

    const left_ident = singleIdentExpr(tokens, call_head.args_start, first_end);
    const right_ident = singleIdentExpr(tokens, second_start, second_end);
    const left_nil = singleNilExpr(tokens, call_head.args_start, first_end);
    const right_nil = singleNilExpr(tokens, second_start, second_end);
    const name = if (left_ident != null and right_nil)
        left_ident.?
    else if (right_ident != null and left_nil)
        right_ident.?
    else
        return null;

    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return null;
    const payload_ty = unionLocalSingleNonNilPayloadType(union_local) orelse return null;
    return .{
        .union_local = union_local,
        .payload_ty = payload_ty,
        .non_nil_when_true = std.mem.eql(u8, call_name, "ne"),
    };
}


pub fn isComparisonNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext) CodegenError!?IsComparisonNarrowing {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "is")) return null;

    const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
    if (first_end != call_head.args_start + 1 or tokens[call_head.args_start].kind != .ident) return null;
    if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return null;
    const union_local = findUnionLocal(locals.union_locals.items, tokens[call_head.args_start].lexeme) orelse return null;
    const type_start = first_end + 1;
    const type_end = trimTrailingComma(tokens, type_start, call_head.args_end);
    if (type_start >= type_end) return null;
    if (findTopLevelToken(tokens, type_start, type_end, "|") != null) return null;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, type_start, type_end, &owned_types)) orelse return null;
    if (parsed_ty.next_idx != type_end) return null;
    const target_ty = try substituteGenericTypeOwned(allocator, parsed_ty.ty, ctx.type_bindings, &owned_types);
    if (std.mem.eql(u8, target_ty, "nil")) return null;
    const branch = findUnionBranchByType(union_local.layout, target_ty) orelse return null;
    if (branch.tag == 0 and std.mem.eql(u8, branch.ty, "nil")) return null;
    // Narrow to payload type so `x [u8] = m` works after `@is(m, Text)`.
    // Flat unions: branch.ty is the arm type. Payload enums: payload_type is the arm payload.
    return .{
        .union_local = union_local,
        .payload_ty = branch.payload_type orelse branch.ty,
    };
}


pub fn singleIdentExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return tokens[range.start].lexeme;
}


pub fn singleNilExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    return range.end == range.start + 1 and tokEq(tokens[range.start], "nil");
}


pub fn unionLocalSingleNonNilPayloadType(union_local: UnionLocal) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}


pub fn unionLocalSingleRemainingPayloadType(union_local: UnionLocal, excluded_ty: []const u8) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (std.mem.eql(u8, branch.ty, excluded_ty)) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}


pub fn trimTrailingComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx < end_idx and tokEq(tokens[end_idx - 1], ",")) return end_idx - 1;
    return end_idx;
}




pub fn applyCollectGuardReturnNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext) !void {
    try applyGuardReturnNilNarrowing(allocator, tokens, start_idx, end_idx, locals);
    try applyGuardReturnIsNarrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}


pub fn mergeReturnCleanupLocals(
    allocator: std.mem.Allocator,
    parent: *const LocalSet,
    direct: *const LocalSet) !LocalSet {
    var out = try cloneLocalSet(allocator, parent);
    errdefer out.deinit(allocator);
    for (direct.locals.items) |local| {
        if (hasLocal(out.locals.items, local.name)) continue;
        try out.locals.append(allocator, local);
    }
    return out;
}


pub fn fieldReflectionScopedCleanupLocalSet(
    allocator: std.mem.Allocator,
    source: *const LocalSet,
    scoped_prefix: []const u8) !LocalSet {
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







