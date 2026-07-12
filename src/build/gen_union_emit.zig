//! Union value / binding emit.
//! Storage / tuple emit and pack helpers.

const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const payload_wat = @import("gen_payload_wat.zig");
const storage_wat = @import("gen_storage_wat.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_collect = @import("gen_collect.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const gen_hooks = @import("gen_hooks.zig");
const findValueEnumDeclLineByName = gen_import.findValueEnumDeclLineByName;
const findValueEnumDeclLineByBranch = gen_import.findValueEnumDeclLineByBranch;
const simpleTypeName = gen_collect.simpleTypeName;
const isTopLevelCommaAny = gen_collect.isTopLevelCommaAny;
const isReturnArrowAt = gen_collect.isReturnArrowAt;
const gen_union = @import("gen_union.zig");
const gen_host = @import("gen_host.zig");
const gen_wasi = @import("gen_wasi.zig");
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
const gen_struct = @import("gen_struct.zig");
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









pub const emitWasiResultReadValues = gen_wasi_emit.emitWasiResultReadValues;
pub const emitWasiResultListU8Values = gen_wasi_emit.emitWasiResultListU8Values;
pub const emitWasiResultDescriptorValues = gen_wasi_emit.emitWasiResultDescriptorValues;
pub const emitWasiResultFilesizeValues = gen_wasi_emit.emitWasiResultFilesizeValues;
pub const emitWasiListU8Arg = gen_wasi_emit.emitWasiListU8Arg;
pub const wasmType = gen_wasi_emit.wasmType;
pub const valueEnumCarrier = gen_wasi_emit.valueEnumCarrier;
pub const codegenScalarType = gen_wasi_emit.codegenScalarType;
// re-export gen_struct












pub fn emitUnionReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    move_names: *std.ArrayList([]const u8),
    defer_ctx: ?*const DeferContext,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    if (start_idx + 1 >= end_idx) return error.NoMatchingCall;
    const expr_start = start_idx + 1;
    const expr_end = end_idx;
    try collectUnionReturnMoveNames(allocator, tokens, expr_start, expr_end, locals, ctx, layout, move_names);
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = end_idx,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    };
    return try emitUnionValue(allocator, tokens, expr_start, expr_end, locals, ctx, layout, false, &move_ctx, out);
}




fn emitUnionValueFromUserFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const func_union = func.result_union orelse return false;
    if (!unionLayoutsAbiCompatible(ctx, func_union, layout)) return false;
    return try gen_hooks.emitUserFuncCallWithMoveContext(
        allocator,
        tokens,
        call_head.args_start,
        call_head.args_end,
        locals,
        ctx,
        func,
        move_ctx,
        out,
    );
}

fn emitUnionValueFromWasi(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    // Thin `return host_...(…)` / expr-position host → exclusive union.
    const wasi_import = findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    return try emitWasiUnitResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, gen_hooks.emitExpr) or
        try emitWasiDescriptorResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, gen_hooks.emitExpr) or
        try emitWasiFilesizeResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, gen_hooks.emitExpr) or
        try emitWasiListU8ResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, gen_hooks.emitExpr) or
        try emitWasiReadResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, gen_hooks.emitExpr);
}

fn emitUnionValueFromCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range: Range,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) {
        if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "field_get")) return false;
        return try emitUnionFieldGetValue(
            allocator,
            tokens,
            call_head.args_start,
            call_head.args_end,
            locals,
            ctx,
            layout,
            copy_managed,
            out,
        );
    }
    if (try emitUnionValueFromUserFunc(allocator, tokens, call_head, locals, ctx, layout, move_ctx, out)) return true;
    return emitUnionValueFromWasi(allocator, tokens, call_head, locals, ctx, layout, out);
}

fn emitUnionValueFromLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range: Range,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    const union_local = findUnionLocal(locals.union_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!unionLayoutsEqual(union_local.layout, layout)) return false;

    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
        if (copy_managed and isManagedLocalType(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try appendUnionTagLocalGet(allocator, out, union_local.name);
    return true;
}

pub fn emitUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (try emitUnionValueFromCall(allocator, tokens, range, locals, ctx, layout, copy_managed, move_ctx, out)) return true;

    if (range.end == range.start + 1 and tokEq(tokens[range.start], "nil")) {
        for (layout.payload_tys) |payload_ty| {
            try emitZeroValueForType(allocator, ctx, out, payload_ty);
        }
        try out.appendSlice(allocator, "    i32.const 0\n");
        return true;
    }

    if (try emitUnionValueFromLocal(allocator, tokens, range, locals, ctx, layout, copy_managed, out)) return true;

    for (layout.branches) |branch| {
        // Flat unions reserve tag 0 for nil; payload enums use case-order tags including 0.
        if (branch.tag == 0 and std.mem.eql(u8, branch.ty, "nil")) continue;
        if (try emitUnionBranchValue(allocator, tokens, range.start, range.end, locals, ctx, layout, branch, copy_managed, out)) {
            return true;
        }
    }
    return false;
}




pub fn emitUnionFieldGetValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != end_idx) return false;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return false;
    const field = fieldFromMeta(ctx, meta) orelse return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const field_layout = (try parseTypeUnionLayoutFromName(allocator, tokens, field.ty, ctx.structs, ctx.struct_layouts, &owned_types)) orelse return false;
    defer freeUnionLayout(allocator, field_layout);
    if (!unionLayoutsEqual(field_layout, layout)) return false;

    const field_name = publicDeclName(field.name);
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ struct_local.name, field_name });
    defer allocator.free(union_local_name);
    const union_local = findUnionLocal(locals.union_locals.items, union_local_name) orelse return false;
    if (!unionLayoutsEqual(union_local.layout, layout)) return false;

    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
        if (copy_managed and isManagedLocalType(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try appendUnionTagLocalGet(allocator, out, union_local.name);
    return true;
}




pub fn emitUnionBranchValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    branch: UnionBranch,
    copy_managed: bool,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);

    // Payload-enum unit case: bare case name `Quit`.
    if (branch.payload_len == 0) {
        if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
            if (!std.mem.eql(u8, publicDeclName(tokens[range.start].lexeme), branch.ty)) return false;
            for (layout.payload_tys) |payload_ty| {
                try emitZeroValueForType(allocator, ctx, out, payload_ty);
            }
            try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
            return true;
        }
        return false;
    }

    // Payload-enum ctor: `Text(expr)` where Text is the case name.
    if (try emitPayloadEnumCtorBranch(
        allocator,
        tokens,
        range,
        locals,
        ctx,
        layout,
        branch,
        copy_managed,
        out,
    )) return true;

    var branch_payload = std.ArrayList(u8).empty;
    defer branch_payload.deinit(allocator);
    if (!try emitUnionBranchPayload(allocator, tokens, start_idx, end_idx, locals, ctx, branch, copy_managed, &branch_payload)) {
        return false;
    }
    try writeUnionBranchSlots(allocator, out, ctx, layout, branch, branch_payload.items);
    return true;
}

fn writeUnionBranchSlots(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ctx: CodegenContext,
    layout: UnionLayout,
    branch: UnionBranch,
    branch_payload: []const u8,
) !void {
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == branch.payload_start) {
            try out.appendSlice(allocator, branch_payload);
        } else if (idx > branch.payload_start and idx < branch.payload_start + branch.payload_len) {
            continue;
        } else {
            try emitZeroValueForType(allocator, ctx, out, payload_ty);
        }
    }
    try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
}

fn emitPayloadEnumCtorBranch(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range: Range,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    branch: UnionBranch,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    if (tokens[call_head.name_idx].kind != .ident) return false;
    if (!std.mem.eql(u8, publicDeclName(tokens[call_head.name_idx].lexeme), branch.ty)) return false;

    const payload_ty = branch.payload_type orelse branch.ty;
    var branch_payload = std.ArrayList(u8).empty;
    defer branch_payload.deinit(allocator);
    if (!try gen_hooks.emitExpr(
        allocator,
        tokens,
        call_head.args_start,
        call_head.args_end,
        locals,
        ctx,
        payload_ty,
        &branch_payload,
    )) return false;

    if (copy_managed and isManagedLocalType(payload_ty, ctx) and
        isDirectManagedLocalExpr(tokens, call_head.args_start, call_head.args_end, locals, ctx))
    {
        try branch_payload.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try writeUnionBranchSlots(allocator, out, ctx, layout, branch, branch_payload.items);
    return true;
}




/// Unmanaged pure-scalar struct local → expand field locals onto the operand stack.
fn emitUnmanagedStructLocalAsPayload(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    range_start: usize,
    range_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    emit_ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!?bool {
    if (range_end != range_start + 1 or tokens[range_start].kind != .ident) return null;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[range_start].lexeme) orelse return null;
    if (!std.mem.eql(u8, struct_local.ty, emit_ty)) return null;
    if (findStructLayout(ctx.struct_layouts, emit_ty) != null) return null;
    const decl = findStructDecl(ctx.structs, emit_ty) orelse return false;
    for (decl.fields) |field| {
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{ struct_local.name, publicDeclName(field.name) });
    }
    return true;
}

pub fn emitUnionBranchPayload(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    branch: UnionBranch,
    copy_managed: bool,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    if (branch.payload_len == 0) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    // Payload-enum cases: emit against payload_type when set (case name ≠ payload type).
    const emit_ty = branch.payload_type orelse branch.ty;

    if (try emitUnmanagedStructLocalAsPayload(allocator, tokens, range.start, range.end, locals, ctx, emit_ty, out)) |handled| {
        return handled;
    }

    if (!try gen_hooks.emitExpr(allocator, tokens, range.start, range.end, locals, ctx, emit_ty, out)) return false;
    if (copy_managed and isManagedLocalType(emit_ty, ctx) and isDirectManagedLocalExpr(tokens, range.start, range.end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}





pub fn unionLayoutsAbiCompatible(ctx: CodegenContext, a: UnionLayout, b: UnionLayout) bool {
    if (a.branches.len != b.branches.len) return false;
    if (a.payload_tys.len != b.payload_tys.len) return false;
    for (a.payload_tys, 0..) |ty, idx| {
        if (!std.mem.eql(u8, codegenWasmType(ctx, ty), codegenWasmType(ctx, b.payload_tys[idx]))) return false;
    }
    for (a.branches, 0..) |branch, idx| {
        const other = b.branches[idx];
        if (branch.tag != other.tag) return false;
        if (branch.payload_start != other.payload_start) return false;
        if (branch.payload_len != other.payload_len) return false;
    }
    return true;
}






pub fn cloneUnionLayoutSubstituted(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    layout: UnionLayout,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8)) !UnionLayout {
    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);
    var source_ty = std.ArrayList(u8).empty;
    errdefer source_ty.deinit(allocator);

    for (layout.branches, 0..) |branch, idx| {
        if (idx != 0) try source_ty.append(allocator, '|');
        const branch_ty = substituteGenericType(branch.ty, bindings);
        try source_ty.appendSlice(allocator, branch_ty);

        const payload_start = payload_tys.items.len;
        if (branch.tag != 0) {
            try appendUnionBranchPayloadTypes(allocator, tokens, branch_ty, structs, struct_layouts, &payload_tys);
        }
        try branches.append(allocator, .{
            .ty = branch_ty,
            .tag = branch.tag,
            .payload_start = payload_start,
            .payload_len = payload_tys.items.len - payload_start,
        });
    }

    const owned_source_ty = try source_ty.toOwnedSlice(allocator);
    errdefer allocator.free(owned_source_ty);
    try owned_types.append(allocator, owned_source_ty);
    return .{
        .source_ty = owned_source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}


/// Build UnionLayout for a named payload enum (tags by case order, max payload slots).
/// Build UnionLayout for a named payload enum (tags by case order, max payload slots).



pub fn buildPayloadEnumUnionLayout(
    allocator: std.mem.Allocator,
    decl: PayloadEnumDecl,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8)) !UnionLayout {
    // Max payload ABI slot count across cases (overlapping slots from 0).
    var max_slots: usize = 0;
    var case_slot_counts = try allocator.alloc(usize, decl.cases.len);
    defer allocator.free(case_slot_counts);
    var case_payload_types = try allocator.alloc(?[]const u8, decl.cases.len);
    defer allocator.free(case_payload_types);

    for (decl.cases, 0..) |case, ci| {
        case_slot_counts[ci] = 0;
        case_payload_types[ci] = null;
        if (case.payload_ty) |pty| {
            var tmp = std.ArrayList([]const u8).empty;
            defer tmp.deinit(allocator);
            try appendUnionBranchPayloadTypes(allocator, tokens, pty, structs, struct_layouts, &tmp);
            case_slot_counts[ci] = tmp.items.len;
            case_payload_types[ci] = pty;
            if (tmp.items.len > max_slots) max_slots = tmp.items.len;
        }
    }

    // Shared payload slots: take types from the first case that fills each slot.
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);
    if (max_slots > 0) {
        var filled = try allocator.alloc(bool, max_slots);
        defer allocator.free(filled);
        @memset(filled, false);
        try payload_tys.resize(allocator, max_slots);
        for (decl.cases) |case| {
            if (case.payload_ty == null) continue;
            var tmp = std.ArrayList([]const u8).empty;
            defer tmp.deinit(allocator);
            try appendUnionBranchPayloadTypes(allocator, tokens, case.payload_ty.?, structs, struct_layouts, &tmp);
            for (tmp.items, 0..) |slot_ty, si| {
                if (filled[si]) continue;
                payload_tys.items[si] = slot_ty;
                filled[si] = true;
            }
        }
        // Any unfilled slot defaults to i32 (should not happen if max_slots correct).
        for (filled, 0..) |ok, si| {
            if (!ok) payload_tys.items[si] = "i32";
        }
    }

    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    for (decl.cases, 0..) |case, ci| {
        try branches.append(allocator, .{
            .ty = case.name,
            .tag = ci, // case-order tags (0..)
            .payload_start = 0,
            .payload_len = case_slot_counts[ci],
            .payload_type = case_payload_types[ci],
        });
    }

    const source_ty = try allocator.dupe(u8, decl.name);
    errdefer allocator.free(source_ty);
    try owned_types.append(allocator, source_ty);
    return .{
        .source_ty = source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}




pub fn findUnionBranchByCompatibleType(layout: UnionLayout, ty: []const u8) ?UnionBranch {
    for (layout.branches) |branch| {
        if (codegenTypesCompatible(branch.ty, ty)) return branch;
    }
    return null;
}





pub fn emitUnionStructPayloadForType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8)) CodegenError!bool {
    if (findNarrowedUnionType(locals.narrowed_union_locals.items, name)) |narrowed_ty| {
        if (!std.mem.eql(u8, narrowed_ty, ty)) return false;
    } else {
        return false;
    }
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return false;
    const payload = unionLocalDefaultStructPayload(tokens, ctx, union_local) orelse return false;
    if (!std.mem.eql(u8, payload.decl.name, ty)) return false;

    if (payload.branch.payload_len == 1) {
        if (findStructLayout(ctx.struct_layouts, payload.decl.name) != null) {
            try appendUnionPayloadLocalGet(allocator, out, union_local.name, payload.branch.payload_start);
            if (copy_managed) try out.appendSlice(allocator, "    call $__arc_inc\n");
            return true;
        }
    }

    var idx = payload.branch.payload_start;
    for (payload.decl.fields) |field| {
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
        if (copy_managed and isManagedLocalType(field.ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        idx += 1;
    }
    return true;
}




pub fn emitUnionIsCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end != args_start + 1 or tokens[args_start].kind != .ident) return false;
    if (first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const union_local = findUnionLocal(locals.union_locals.items, tokens[args_start].lexeme) orelse return false;
    const type_start = first_end + 1;
    const type_end = args_end;

    var tags = std.ArrayList(usize).empty;
    defer tags.deinit(allocator);
    try collectUnionIsTags(allocator, tokens, type_start, type_end, ctx, union_local.layout, &tags);
    if (tags.items.len == 0) return false;

    for (tags.items, 0..) |tag, idx| {
        try appendUnionTagLocalGet(allocator, out, union_local.name);
        try appendFmt(allocator, out, "    i32.const {d}\n", .{tag});
        try out.appendSlice(allocator, "    i32.eq\n");
        if (idx != 0) try out.appendSlice(allocator, "    i32.or\n");
    }
    return true;
}




pub fn collectUnionIsTags(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    layout: UnionLayout,
    out: *std.ArrayList(usize)) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    var branch_start = start_idx;
    while (branch_start < end_idx) {
        if (tokEq(tokens[branch_start], "|")) {
            branch_start += 1;
            continue;
        }
        const branch_end = findTopLevelToken(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start) return error.NoMatchingCall;
        if (branch_end == branch_start + 1 and tokEq(tokens[branch_start], "nil")) return error.NoMatchingCall;
        const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, branch_start, branch_end, &owned_types)) orelse return error.NoMatchingCall;
        if (parsed_ty.next_idx != branch_end) return error.NoMatchingCall;
        const branch = findUnionBranchByType(layout, parsed_ty.ty) orelse return error.NoMatchingCall;
        if (branch.tag == 0 and std.mem.eql(u8, branch.ty, "nil")) return error.NoMatchingCall;
        try out.append(allocator, branch.tag);
        branch_start = branch_end;
        if (branch_start < end_idx and tokEq(tokens[branch_start], "|")) branch_start += 1;
    }

    _ = ctx;
}




pub fn emitUnionNilComparison(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    move_ctx: ?*const CallLastUseMoveContext,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = unionLocalSingleIdent(tokens, args_start, first_end, locals);
    const second_union = unionLocalSingleIdent(tokens, second_start, second_end, locals);
    const first_nil = first_end == args_start + 1 and tokEq(tokens[args_start], "nil");
    const second_nil = second_end == second_start + 1 and tokEq(tokens[second_start], "nil");

    if (first_union != null and second_nil) {
        try appendUnionTagLocalGet(allocator, out, first_union.?.name);
    } else if (second_union != null and first_nil) {
        try appendUnionTagLocalGet(allocator, out, second_union.?.name);
    } else if (second_nil) {
        if (!try emitUnionExprTagAndDiscardPayload(allocator, tokens, args_start, first_end, move_ctx, locals, ctx, out)) {
            return false;
        }
    } else if (first_nil) {
        if (!try emitUnionExprTagAndDiscardPayload(allocator, tokens, second_start, second_end, move_ctx, locals, ctx, out)) {
            return false;
        }
    } else {
        return false;
    }
    try out.appendSlice(allocator, "    i32.const 0\n");
    if (std.mem.eql(u8, call_name, "eq")) {
        try out.appendSlice(allocator, "    i32.eq\n");
    } else {
        try out.appendSlice(allocator, "    i32.ne\n");
    }
    return true;
}




pub fn emitUnionExprTagAndDiscardPayload(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    move_ctx: ?*const CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const layout = func.result_union orelse return false;
    if (!try gen_hooks.emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, move_ctx, out)) {
        return false;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    var idx = layout.payload_tys.len;
    while (idx > 0) {
        idx -= 1;
        if (isManagedLocalType(layout.payload_tys[idx], ctx)) {
            try out.appendSlice(allocator, "    call $__arc_dec\n");
        } else {
            try out.appendSlice(allocator, "    drop\n");
        }
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}




pub fn unionPayloadComparisonCallBranch(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?UnionBranch {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return null;
    const range = trimParens(tokens, args_start, first_end);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return null;
    const layout = func.result_union orelse return null;
    return unionPayloadComparisonBranchForValue(tokens, second_start, second_end, locals, ctx, layout);
}




pub fn emitUnionErrorBranchComparison(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = unionLocalSingleIdent(tokens, args_start, first_end, locals);
    const second_union = unionLocalSingleIdent(tokens, second_start, second_end, locals);
    const union_local = first_union orelse second_union orelse return false;
    const value_start = if (first_union != null) second_start else args_start;
    const value_end = if (first_union != null) second_end else first_end;

    for (union_local.layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1) continue;
        const branch_value = errorBranchValueForComparison(allocator, ctx, tokens, value_start, value_end, branch.ty) orelse continue;
        try appendUnionTagLocalGet(allocator, out, union_local.name);
        try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
        try out.appendSlice(allocator, "    i32.eq\n");
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, branch.payload_start);
        try appendFmt(allocator, out, "    i32.const {d}\n", .{branch_value});
        try out.appendSlice(allocator, "    i32.eq\n");
        try out.appendSlice(allocator, "    i32.and\n");
        if (std.mem.eql(u8, call_name, "ne")) {
            try out.appendSlice(allocator, "    i32.eqz\n");
        }
        return true;
    }
    return false;
}




pub fn errorBranchValueForComparison(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    error_ty: []const u8,
) ?usize {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return null;
    const name = tokens[range.start].lexeme;
    if (errorEnumBranchValue(tokens, error_ty, name)) |value| return value;
    return importedErrorBranchValue(allocator, ctx.imported_alias_ctx, tokens, name, error_ty);
}




pub fn emitUnionLocalPayloadForType(
    allocator: std.mem.Allocator,
    name: []const u8,
    ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return false;
    const narrowed_ty = findNarrowedUnionType(locals.narrowed_union_locals.items, name) orelse
        return error.UnionPayloadRequiresNarrowing;
    const concrete_narrowed_ty = substituteGenericType(narrowed_ty, ctx.type_bindings);

    // Prefer branch matching the narrowed payload/arm type.
    var matched: ?UnionBranch = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len == 0) continue;
        const branch_payload_ty = branch.payload_type orelse branch.ty;
        const concrete_branch_ty = substituteGenericType(branch_payload_ty, ctx.type_bindings);
        // Match narrowed type to case name or payload type.
        const matches_narrow = codegenTypesCompatible(concrete_branch_ty, concrete_narrowed_ty) or
            std.mem.eql(u8, branch.ty, concrete_narrowed_ty);
        if (!matches_narrow) continue;
        if (!codegenTypesCompatible(concrete_branch_ty, ty) and !codegenTypesCompatible(branch.ty, ty)) continue;
        if (matched != null) {
            // Ambiguous (e.g. Text vs Binary both [u8]): require unique match by case... 
            // but narrowing stores payload type only. For same-payload cases, any matching branch works
            // for ABI (same slot layout); use first match.
            break;
        }
        matched = branch;
    }
    if (matched == null) {
        for (union_local.layout.branches) |branch| {
            if (branch.payload_len != 1) continue;
            const branch_payload_ty = branch.payload_type orelse branch.ty;
            const concrete_branch_ty = substituteGenericType(branch_payload_ty, ctx.type_bindings);
            if (!codegenTypesCompatible(concrete_branch_ty, ty) and !codegenTypesCompatible(branch.ty, ty)) continue;
            if (matched != null) return false;
            matched = branch;
        }
    }
    const branch = matched orelse return false;

    const branch_payload_ty = branch.payload_type orelse branch.ty;
    if (!codegenTypesCompatible(concrete_narrowed_ty, ty) and
        !std.mem.eql(u8, concrete_narrowed_ty, branch.ty) and
        !codegenTypesCompatible(concrete_narrowed_ty, branch_payload_ty))
        return false;

    try appendUnionPayloadLocalGet(allocator, out, union_local.name, branch.payload_start);
    return true;
}





/// Pop ABI union slots from the stack into `union_local` (payloads then tag).
fn storeUnionLocalFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    union_local: UnionLocal,
) !void {
    var idx = union_local.layout.payload_tys.len + 1;
    while (idx > 0) {
        idx -= 1;
        if (idx == union_local.layout.payload_tys.len) {
            try appendUnionTagLocalSet(allocator, out, union_local.name);
        } else {
            try appendUnionPayloadLocalSet(allocator, out, union_local.name, idx);
        }
    }
}

fn emitUnionBindingFromUserFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    union_local: UnionLocal,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const func_union = func.result_union orelse return false;
    if (!unionLayoutsAbiCompatible(ctx, func_union, union_local.layout)) return false;

    if (!try gen_hooks.emitUserFuncCallWithUnionBindingMove(
        allocator,
        tokens,
        call_head.args_start,
        call_head.args_end,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        func,
        out,
    )) return error.NoMatchingCall;

    try storeUnionLocalFromStack(allocator, out, union_local);
    return true;
}

fn emitUnionBindingFromWasi(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    union_local: UnionLocal,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    // Fallible host result-area → exclusive do union (`nil|i32`, `Dir|i32`, …).
    const wasi_import = findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    const emitted =
        try emitWasiUnitResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, gen_hooks.emitExpr) or
        try emitWasiDescriptorResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, gen_hooks.emitExpr) or
        try emitWasiFilesizeResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, gen_hooks.emitExpr) or
        try emitWasiListU8ResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, gen_hooks.emitExpr) or
        try emitWasiReadResultAsUnionValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, gen_hooks.emitExpr);
    if (!emitted) return false;

    try storeUnionLocalFromStack(allocator, out, union_local);
    return true;
}

fn emitUnionBindingFromCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    rhs_range: Range,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    union_local: UnionLocal,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;

    if (try emitUnionBindingFromUserFunc(
        allocator,
        tokens,
        call_head,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        union_local,
        out,
    )) return true;

    return emitUnionBindingFromWasi(allocator, tokens, call_head, locals, ctx, union_local, out);
}

pub fn emitUnionBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const union_local = findUnionLocal(locals.union_locals.items, tokens[start_idx].lexeme) orelse return false;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);

    if (try emitUnionBindingFromCall(
        allocator,
        tokens,
        rhs_range,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        union_local,
        out,
    )) return true;

    if (!try emitUnionValue(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, union_local.layout, true, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    try storeUnionLocalFromStack(allocator, out, union_local);
    return true;
}




pub fn emitUnionStructFieldGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    field_tok: lexer.Token,
    single_field_arg: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    if (!single_field_arg or !isDotIdent(field_tok.lexeme)) return false;
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return false;
    const payload = unionLocalDefaultStructPayload(tokens, ctx, union_local) orelse return false;
    const field_name = publicDeclName(field_tok.lexeme);
    const field_offset = structFieldPayloadOffset(payload.decl, field_name) orelse return false;

    if (payload.branch.payload_len == 1) {
        if (findStructLayout(ctx.struct_layouts, payload.decl.name)) |layout| {
            const field_ty = findStructFieldType(payload.decl, field_name) orelse return false;
            try appendUnionPayloadLocalGet(allocator, out, name, payload.branch.payload_start);
            try out.appendSlice(allocator, "    call $__arc_payload\n");
            try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, field_ty);
            if (isManagedStructField(layout, field_name)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            return true;
        }
    }

    var idx = payload.branch.payload_start;
    var offset: usize = 0;
    for (payload.decl.fields) |field| {
        offset = alignUp(offset, typePayloadAlignment(field.ty));
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) {
            try appendUnionPayloadLocalGet(allocator, out, name, idx);
            return true;
        }
        offset += typePayloadBytes(field.ty);
        idx += 1;
    }
    return false;
}



pub fn importedErrorBranchValue(
    allocator: std.mem.Allocator,
    imported_alias_ctx: ?ImportedAliasContext,
    tokens: []const lexer.Token,
    name: []const u8,
    enum_name: []const u8,
) ?usize {
    const ctx = imported_alias_ctx orelse return null;
    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    const child_idx = findImportedModuleIndex(allocator, ctx.graph, ctx.module_idx, import_ref) orelse return null;
    return errorEnumBranchValue(ctx.graph.modules[child_idx].tokens, enum_name, import_ref.target);
}



pub fn collectUnionReturnMoveNames(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    move_names: *std.ArrayList([]const u8)) !void {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return;
    const name = tokens[range.start].lexeme;
    if (findUnionLocal(locals.union_locals.items, name)) |union_local| {
        if (!unionLayoutsAbiCompatible(ctx, union_local.layout, layout)) return;
        for (layout.payload_tys, 0..) |payload_ty, idx| {
            if (!isManagedLocalType(payload_ty, ctx)) continue;
            const payload_name = try unionPayloadLocalName(allocator, union_local.name, idx);
            defer allocator.free(payload_name);
            const local_name = findLocalName(locals.locals.items, payload_name) orelse return;
            try move_names.append(allocator, local_name);
        }
        return;
    }
    const raw_ty = findLocalType(locals.locals.items, name) orelse return;
    const ty = substituteGenericType(raw_ty, ctx.type_bindings);
    if (!isManagedLocalType(ty, ctx)) return;
    if (findUnionBranchByCompatibleType(layout, ty) == null and !unionLayoutHasSinglePayloadAbiType(ctx, layout, ty)) return;
    try move_names.append(allocator, findLocalName(locals.locals.items, name) orelse name);
}


pub fn unionLayoutHasSinglePayloadAbiType(ctx: CodegenContext, layout: UnionLayout, ty: []const u8) bool {
    const target_wasm_ty = codegenWasmType(ctx, ty);
    for (layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        const payload_ty = layout.payload_tys[branch.payload_start];
        if (std.mem.eql(u8, codegenWasmType(ctx, payload_ty), target_wasm_ty)) return true;
    }
    return false;
}


pub fn unionPayloadComparisonBranchForValue(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
) ?UnionBranch {
    if (layout.payload_tys.len != 1) return null;
    for (layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1 or branch.payload_start != 0) continue;
        if (!isCodegenScalarType(ctx, branch.ty)) continue;
        if (!callArgMatchesParam(tokens, value_start, value_end, locals, ctx, branch.ty)) continue;
        return branch;
    }
    return null;
}


pub fn emitUnionPayloadComparisonCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;
    const range = trimParens(tokens, args_start, first_end);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const layout = func.result_union orelse return false;
    const branch = unionPayloadComparisonBranchForValue(tokens, second_start, second_end, locals, ctx, layout) orelse return false;

    if (!try gen_hooks.emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, null, out)) {
        return false;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (!try gen_hooks.emitExpr(allocator, tokens, second_start, second_end, locals, ctx, branch.ty, out)) {
        return false;
    }
    const op_ty = codegenScalarType(ctx, branch.ty);
    const eq_op = comparisonWasmOp("eq", op_ty) orelse return false;
    try appendFmt(allocator, out, "    {s}\n", .{eq_op});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    i32.and\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}


pub fn emitUnionPayloadComparisonLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = unionLocalSingleIdent(tokens, args_start, first_end, locals);
    const second_union = unionLocalSingleIdent(tokens, second_start, second_end, locals);
    if (first_union != null and second_union != null) return false;

    const union_local = first_union orelse second_union orelse return false;
    const value_start = if (first_union != null) second_start else args_start;
    const value_end = if (first_union != null) second_end else first_end;
    const branch = unionPayloadComparisonBranchForLocalValue(tokens, value_start, value_end, locals, ctx, union_local.layout) orelse return false;

    try appendUnionPayloadLocalGet(allocator, out, union_local.name, branch.payload_start);
    if (!try gen_hooks.emitExpr(allocator, tokens, value_start, value_end, locals, ctx, branch.ty, out)) {
        return false;
    }
    const op_ty = codegenScalarType(ctx, branch.ty);
    const eq_op = comparisonWasmOp("eq", op_ty) orelse return false;
    try appendFmt(allocator, out, "    {s}\n", .{eq_op});
    try appendUnionTagLocalGet(allocator, out, union_local.name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    i32.and\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}


pub fn unionPayloadComparisonBranchForLocalValue(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
) ?UnionBranch {
    for (layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1) continue;
        if (!isCodegenScalarType(ctx, branch.ty)) continue;
        if (!callArgMatchesParam(tokens, value_start, value_end, locals, ctx, branch.ty)) continue;
        return branch;
    }
    return null;
}


pub fn unionLocalSingleIdent(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?UnionLocal {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return null;
    return findUnionLocal(locals.union_locals.items, tokens[range.start].lexeme);
}


pub fn findStorageReadableLocalName(
    tokens: []const lexer.Token,
    locals: *const LocalSet,
    name: []const u8,
) ?[]const u8 {
    _ = tokens;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, name)) |storage| return storage.name;

    const ty = findNarrowedUnionType(locals.narrowed_union_locals.items, name) orelse return null;
    if (storageElemTypeFromName(ty) == null) return null;
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return null;

    var matched: ?UnionBranch = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        if (!codegenTypesCompatible(branch.ty, ty)) continue;
        if (matched != null) return null;
        matched = branch;
    }
    const branch = matched orelse return null;
    return unionPayloadLocalNameFromLocals(locals.locals.items, union_local.name, branch.payload_start);
}


pub fn emitUnionStoragePayloadGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    index_start: usize,
    index_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) CodegenError!bool {
    const ty = findNarrowedUnionType(locals.narrowed_union_locals.items, name) orelse return false;
    const elem_ty = storageElemTypeFromName(ty) orelse return false;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    const storage_name = findStorageReadableLocalName(tokens, locals, name) orelse return false;

    try emitStorageBoundsCheck(allocator, tokens, index_start, index_end, locals, ctx, storage_name, 1, out);
    if (isTupleTypeName(elem_ty)) {
        try emitStorageDataPtr(allocator, out, storage_name);
        if (!try gen_hooks.emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
        if (elem_bytes != 1) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendLoadTupleLeavesOwningToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emitStorageDataPtr(allocator, out, storage_name);
        if (!try gen_hooks.emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
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


pub fn isCodegenScalarType(ctx: CodegenContext, ty: []const u8) bool {
    return isCoreWasmScalar(ty) or valueEnumCarrier(ctx, ty) != null;
}


pub fn isUnsignedScalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "u8") or
        std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "u32") or
        std.mem.eql(u8, ty, "u64") or
        std.mem.eql(u8, ty, "usize");
}


pub fn comparisonWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "eq")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.eq";
        if (std.mem.eql(u8, wt, "f32")) return "f32.eq";
        if (std.mem.eql(u8, wt, "f64")) return "f64.eq";
        return "i32.eq";
    }
    if (std.mem.eql(u8, name, "ne")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.ne";
        if (std.mem.eql(u8, wt, "f32")) return "f32.ne";
        if (std.mem.eql(u8, wt, "f64")) return "f64.ne";
        return "i32.ne";
    }
    if (std.mem.eql(u8, name, "lt")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.lt_u" else "i64.lt_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.lt";
        if (std.mem.eql(u8, wt, "f64")) return "f64.lt";
        return if (isUnsignedScalar(ty)) "i32.lt_u" else "i32.lt_s";
    }
    if (std.mem.eql(u8, name, "le")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.le_u" else "i64.le_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.le";
        if (std.mem.eql(u8, wt, "f64")) return "f64.le";
        return if (isUnsignedScalar(ty)) "i32.le_u" else "i32.le_s";
    }
    if (std.mem.eql(u8, name, "gt")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.gt_u" else "i64.gt_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.gt";
        if (std.mem.eql(u8, wt, "f64")) return "f64.gt";
        return if (isUnsignedScalar(ty)) "i32.gt_u" else "i32.gt_s";
    }
    if (std.mem.eql(u8, name, "ge")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.ge_u" else "i64.ge_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.ge";
        if (std.mem.eql(u8, wt, "f64")) return "f64.ge";
        return if (isUnsignedScalar(ty)) "i32.ge_u" else "i32.ge_s";
    }
    return null;
}


