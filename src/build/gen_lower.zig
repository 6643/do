const std = @import("std");
const backend_ir = @import("backend_ir.zig");
const component_metadata_wat = @import("component_metadata_wat.zig");
const function_body_wat = @import("function_body_wat.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const parser = @import("parser.zig");
const payload_wat = @import("gen_payload_wat.zig");
const runtime_prelude_wat = @import("runtime_prelude_wat.zig");
const storage_wat = @import("gen_storage_wat.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const gen_util = @import("gen_util.zig");
const gen_wasi = @import("gen_wasi.zig");
const gen_union = @import("gen_union.zig");
const gen_types = @import("gen_types.zig");

const LocalSet = gen_types.LocalSet;
const ValueEnumBranch = gen_types.ValueEnumBranch;
const PayloadEnumCase = gen_types.PayloadEnumCase;
const ManagedFieldOffset = gen_types.ManagedFieldOffset;
const TypedStructBinding = gen_types.TypedStructBinding;
const InferredUnionBinding = gen_types.InferredUnionBinding;
const TYPE_ID_STORAGE_U8 = gen_types.TYPE_ID_STORAGE_U8;
const TYPE_ID_STORAGE_MANAGED = gen_types.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_FIRST_STRUCT = gen_types.TYPE_ID_FIRST_STRUCT;
const STORAGE_PAYLOAD_HEADER_BYTES = gen_types.STORAGE_PAYLOAD_HEADER_BYTES;
const STORAGE_PUT_SOURCE_TMP_LOCAL = gen_types.STORAGE_PUT_SOURCE_TMP_LOCAL;
const VARIADIC_PACK_TMP_LOCAL = gen_types.VARIADIC_PACK_TMP_LOCAL;
const STORAGE_WRITE_INDEX_TMP_LOCAL = gen_types.STORAGE_WRITE_INDEX_TMP_LOCAL;
const STORAGE_WRITE_LEN_TMP_LOCAL = gen_types.STORAGE_WRITE_LEN_TMP_LOCAL;
const STORAGE_WRITE_NEXT_TMP_LOCAL = gen_types.STORAGE_WRITE_NEXT_TMP_LOCAL;
const STORAGE_WRITE_SCAN_TMP_LOCAL = gen_types.STORAGE_WRITE_SCAN_TMP_LOCAL;
const STORAGE_WRITE_TARGET_TMP_LOCAL = gen_types.STORAGE_WRITE_TARGET_TMP_LOCAL;
const TUPLE_PACK_BASE_TMP_LOCAL = gen_types.TUPLE_PACK_BASE_TMP_LOCAL;
const TUPLE_PACK_SPILL_I32 = gen_types.TUPLE_PACK_SPILL_I32;
const TUPLE_PACK_SPILL_I64 = gen_types.TUPLE_PACK_SPILL_I64;
const TUPLE_PACK_SPILL_F32 = gen_types.TUPLE_PACK_SPILL_F32;
const TUPLE_PACK_SPILL_F64 = gen_types.TUPLE_PACK_SPILL_F64;
const NUMERIC_SELECT_LEFT_TMP_I32 = gen_types.NUMERIC_SELECT_LEFT_TMP_I32;
const NUMERIC_SELECT_RIGHT_TMP_I32 = gen_types.NUMERIC_SELECT_RIGHT_TMP_I32;
const NUMERIC_SELECT_LEFT_TMP_I64 = gen_types.NUMERIC_SELECT_LEFT_TMP_I64;
const NUMERIC_SELECT_RIGHT_TMP_I64 = gen_types.NUMERIC_SELECT_RIGHT_TMP_I64;
const EMPTY_LOCAL_SET = gen_types.EMPTY_LOCAL_SET;
const OwnedFuncTypeShape = gen_types.OwnedFuncTypeShape;
const CallbackBindingKind = gen_types.CallbackBindingKind;
const FuncResultParse = gen_types.FuncResultParse;
const MultiResultLhsKind = gen_types.MultiResultLhsKind;
const NO_RESULT_ITEMS = gen_types.NO_RESULT_ITEMS;
const ParsedCodegenType = gen_types.ParsedCodegenType;
const StructFieldAbiSlot = gen_types.StructFieldAbiSlot;
const FuncBodyShape = gen_types.FuncBodyShape;
const StructErrorResult = gen_types.StructErrorResult;
const NilComparisonNarrowing = gen_types.NilComparisonNarrowing;
const IsComparisonNarrowing = gen_types.IsComparisonNarrowing;
const CodegenImportPrefix = gen_types.CodegenImportPrefix;
const CodegenImportRef = gen_types.CodegenImportRef;
const ImportedScalarConst = gen_types.ImportedScalarConst;
const findStorageLocalOrigin = gen_types.findStorageLocalOrigin;
const isCompilerLocalName = gen_types.isCompilerLocalName;
const unionPayloadLocalName = gen_types.unionPayloadLocalName;
const unionTagLocalName = gen_types.unionTagLocalName;
const findUnionLocalExact = gen_types.findUnionLocalExact;
const appendLoopSourceStorageLocal = gen_types.appendLoopSourceStorageLocal;
const localNameMatches = gen_types.localNameMatches;
const loopSourceLocalName = gen_types.loopSourceLocalName;
const freeCallbackBindings = gen_types.freeCallbackBindings;
pub const freeStructDecls = gen_types.freeStructDecls;
const freeStructDecl = gen_types.freeStructDecl;
const freeValueEnumDecls = gen_types.freeValueEnumDecls;
const freePayloadEnumDecls = gen_types.freePayloadEnumDecls;
pub const freeStructLayouts = gen_types.freeStructLayouts;
pub const freeFuncParams = gen_types.freeFuncParams;
pub const freeFuncDecls = gen_types.freeFuncDecls;
const freeFuncResultItems = gen_types.freeFuncResultItems;
const freeWasiHostImports = gen_wasi.freeWasiHostImports;
const collectWasiHostImports = gen_wasi.collectWasiHostImports;
const collectWasiHostImportsFromModules = gen_wasi.collectWasiHostImportsFromModules;
const wasiLowering = gen_wasi.wasiLowering;
const appendWasiImportSymbol = gen_wasi.appendWasiImportSymbol;
const ManagedPayloadBinding = gen_storage.ManagedPayloadBinding;
const ParsedStorageType = gen_storage.ParsedStorageType;
const Local = gen_types.Local;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const EmitOptions = gen_types.EmitOptions;
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
const DeferItem = gen_types.DeferItem;
const DeferItemKind = gen_types.DeferItemKind;
const LoopControl = gen_types.LoopControl;
const CollectionLoopHeader = gen_types.CollectionLoopHeader;
const RecvLoopHeader = gen_types.RecvLoopHeader;
const FieldReflectionLoopHeader = gen_types.FieldReflectionLoopHeader;
const FieldStaticValue = gen_types.FieldStaticValue;
const FieldReflectionIfParts = gen_types.FieldReflectionIfParts;
const FieldMetaLocal = gen_types.FieldMetaLocal;
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
const StringData = gen_types.StringData;
const SourceOrigin = gen_types.SourceOrigin;
const ReachVisit = gen_types.ReachVisit;
const MultiResultLhs = gen_types.MultiResultLhs;
const NumericSelectTemps = gen_types.NumericSelectTemps;
const SelfTailTco = gen_types.SelfTailTco;
const ExprCallHead = gen_types.ExprCallHead;
const STORAGE_OVERWRITE_TMP_LOCAL = gen_types.STORAGE_OVERWRITE_TMP_LOCAL;
const STRUCT_LITERAL_TMP_LOCAL = gen_types.STRUCT_LITERAL_TMP_LOCAL;
const findLocalType = gen_types.findLocalType;
const findLocalOrigin = gen_types.findLocalOrigin;
const findStorageLocal = gen_types.findStorageLocal;
const findStructLocal = gen_types.findStructLocal;
const findUnionLocal = gen_types.findUnionLocal;
const hasLocal = gen_types.hasLocal;
const storageTypeNameForElem = gen_types.storageTypeNameForElem;
const storageTypeNameForElemOwned = gen_types.storageTypeNameForElemOwned;

const UnionLayout = gen_union.UnionLayout;
const UnionBranch = gen_union.UnionBranch;
const freeUnionLayout = gen_union.freeUnionLayout;
const cloneUnionLayout = gen_union.cloneUnionLayout;
const unionLayoutsEqual = gen_union.unionLayoutsEqual;

const WasiHostImport = gen_wasi.WasiHostImport;
const validateWasiHostImportBuildUses = gen_wasi.validateWasiHostImportBuildUses;
const WASI_BINDING_ENTRY_SOURCE = gen_wasi.WASI_BINDING_ENTRY_SOURCE;

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
const decodeQuotedStringToken = gen_util.decodeQuotedStringToken;
const hasString = gen_util.hasString;
const findTopLevelTypeSeparator = gen_util.findTopLevelTypeSeparator;
const findTopLevelTypeSeparatorFrom = gen_util.findTopLevelTypeSeparatorFrom;

pub const CallLastUseMoveContext = gen_types.CallLastUseMoveContext;
const gen_host = @import("gen_host.zig");
const gen_import = @import("gen_import.zig");
const gen_collect = @import("gen_collect.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const tupleElementTypeAt = gen_wasi_emit.tupleElementTypeAt;
const tupleScalarLeafStorageByteWidthCtx = gen_wasi_emit.tupleScalarLeafStorageByteWidthCtx;
const findStoragePrimitiveLocal = gen_wasi_emit.findStoragePrimitiveLocal;
const isStorageTypeName = gen_wasi_emit.isStorageTypeName;
const tupleArity = gen_wasi_emit.tupleArity;
const isTupleTypeName = gen_wasi_emit.isTupleTypeName;
const gen_hooks = @import("gen_hooks.zig");
const gen_storage = @import("gen_storage.zig");
const gen_expr = @import("gen_expr.zig");
const gen_generic = @import("gen_generic.zig");
const collectBodyLocalsWithMode = gen_expr.collectBodyLocalsWithMode;
// re-export gen_expr
const emitStartFunc = gen_expr.emitStartFunc;
pub const emitScalarNumericStartWithBackendIr = gen_expr.emitScalarNumericStartWithBackendIr;
const emitTestFuncs = gen_expr.emitTestFuncs;
const emitUserFuncs = gen_expr.emitUserFuncs;

// Re-export generic instantiation (physical home: gen_generic.zig).
pub const appendUnmanagedStructResultAbi = gen_generic.appendUnmanagedStructResultAbi;
pub const bindExplicitGenericCallTypeArgs = gen_generic.bindExplicitGenericCallTypeArgs;
pub const bindGenericCallbackArg = gen_generic.bindGenericCallbackArg;
pub const bindGenericCallbackIdentArg = gen_generic.bindGenericCallbackIdentArg;
pub const bindGenericCallbackLambdaArg = gen_generic.bindGenericCallbackLambdaArg;
pub const bindGenericExpectedResult = gen_generic.bindGenericExpectedResult;
pub const bindGenericFuncCall = gen_generic.bindGenericFuncCall;
pub const bindGenericTypeFromConcrete = gen_generic.bindGenericTypeFromConcrete;
pub const bindGenericTypeListFromConcrete = gen_generic.bindGenericTypeListFromConcrete;
pub const bindGenericVariadicTail = gen_generic.bindGenericVariadicTail;
pub const callbackBindingsForCall = gen_generic.callbackBindingsForCall;
pub const callbackBindingsHaveSameConcreteArgs = gen_generic.callbackBindingsHaveSameConcreteArgs;
pub const cloneFuncParams = gen_generic.cloneFuncParams;
pub const cloneGenericTypeBindingsOwned = gen_generic.cloneGenericTypeBindingsOwned;
pub const collectConcreteCallbackFuncInstanceForCall = gen_generic.collectConcreteCallbackFuncInstanceForCall;
pub const collectGenericFuncInstanceForCall = gen_generic.collectGenericFuncInstanceForCall;
pub const collectGenericFuncInstancesForCall = gen_generic.collectGenericFuncInstancesForCall;
pub const collectGenericFuncInstancesForConcreteFuncs = gen_generic.collectGenericFuncInstancesForConcreteFuncs;
pub const collectGenericFuncInstancesForStart = gen_generic.collectGenericFuncInstancesForStart;
pub const collectGenericFuncInstancesForTests = gen_generic.collectGenericFuncInstancesForTests;
pub const collectGenericFuncInstancesInCallArgs = gen_generic.collectGenericFuncInstancesInCallArgs;
pub const collectGenericFuncInstancesInFieldReflectionLoop = gen_generic.collectGenericFuncInstancesInFieldReflectionLoop;
pub const collectGenericFuncInstancesInGuardLoopControl = gen_generic.collectGenericFuncInstancesInGuardLoopControl;
pub const collectGenericFuncInstancesInGuardReturn = gen_generic.collectGenericFuncInstancesInGuardReturn;
pub const collectGenericFuncInstancesInRange = gen_generic.collectGenericFuncInstancesInRange;
pub const collectGenericFuncInstancesInStartBody = gen_generic.collectGenericFuncInstancesInStartBody;
pub const concreteOverloadCoversGenericParams = gen_generic.concreteOverloadCoversGenericParams;
pub const directCallExpectedResultType = gen_generic.directCallExpectedResultType;
pub const explicitLambdaTypesMatch = gen_generic.explicitLambdaTypesMatch;
pub const findGenericTemplateForCall = gen_generic.findGenericTemplateForCall;
pub const funcHasUntypedParams = gen_generic.funcHasUntypedParams;
pub const funcParamsHaveSameConcreteCallShape = gen_generic.funcParamsHaveSameConcreteCallShape;
pub const genericBindingsCoverTypeParams = gen_generic.genericBindingsCoverTypeParams;
pub const genericInstanceName = gen_generic.genericInstanceName;
pub const genericOverloadCoversGenericParams = gen_generic.genericOverloadCoversGenericParams;
pub const genericTemplateLogicalResultType = gen_generic.genericTemplateLogicalResultType;
pub const genericTemplateMatchesCallSite = gen_generic.genericTemplateMatchesCallSite;
pub const genericTemplateMatchesConcreteParams = gen_generic.genericTemplateMatchesConcreteParams;
pub const genericTemplateSpecificity = gen_generic.genericTemplateSpecificity;
pub const inferGenericCallUnionResultLayout = gen_generic.inferGenericCallUnionResultLayout;
pub const inferUntypedGenericParamAbiType = gen_generic.inferUntypedGenericParamAbiType;
pub const instantiateCallbackShape = gen_generic.instantiateCallbackShape;
pub const instantiateFuncTypeShape = gen_generic.instantiateFuncTypeShape;
pub const instantiateGenericFuncResultItems = gen_generic.instantiateGenericFuncResultItems;
pub const matchOrBindGenericType = gen_generic.matchOrBindGenericType;
pub const parseLambdaParamNames = gen_generic.parseLambdaParamNames;
pub const parseLambdaParamTypes = gen_generic.parseLambdaParamTypes;
pub const prebindGenericCallbackArg = gen_generic.prebindGenericCallbackArg;
pub const prebindGenericCallbackArgs = gen_generic.prebindGenericCallbackArgs;
pub const prebindGenericCallbackFuncRef = gen_generic.prebindGenericCallbackFuncRef;
pub const prebindGenericCallbackIdent = gen_generic.prebindGenericCallbackIdent;
pub const prebindGenericCallbackLambda = gen_generic.prebindGenericCallbackLambda;
pub const prebindGenericTypeIfParam = gen_generic.prebindGenericTypeIfParam;
pub const resolveCallbackBindingArg = gen_generic.resolveCallbackBindingArg;
pub const typeContainsTypeParam = gen_generic.typeContainsTypeParam;
pub const typedBindingExpectedType = gen_generic.typedBindingExpectedType;

pub fn collectBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) anyerror!void {
    installGenHooks();
    return gen_expr.collectBodyLocals(allocator, tokens, start_idx, end_idx, ctx, out);
}
const directManagedCallLastUseMoveSource = gen_expr.directManagedCallLastUseMoveSource;
const directManagedUnionBindingCallMoveSource = gen_expr.directManagedUnionBindingCallMoveSource;
const emitMultiResultAssignment = gen_expr.emitMultiResultAssignment;
pub fn emitExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    installGenHooks();
    return gen_expr.emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, out);
}
pub fn emitExprWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    installGenHooks();
    return gen_expr.emitExprWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, move_ctx, out);
}
const emitBareUserFuncCall = gen_expr.emitBareUserFuncCall;
const emitBareUserFuncCallWithMoveContext = gen_expr.emitBareUserFuncCallWithMoveContext;
const appendFuncParamLocals = gen_expr.appendFuncParamLocals;
const funcHasCallbackParams = gen_expr.funcHasCallbackParams;
const emitUserFuncCallWithMoveContext = gen_expr.emitUserFuncCallWithMoveContext;
const emitUserFuncCallWithUnionBindingMove = gen_expr.emitUserFuncCallWithUnionBindingMove;
const gen_ctrl = @import("gen_ctrl.zig");
// re-export gen_ctrl
const fieldReflectionLoopHeader = gen_ctrl.fieldReflectionLoopHeader;
const emitBody = gen_ctrl.emitBody;
const appendConditionNarrowingForBranch = gen_ctrl.appendConditionNarrowingForBranch;
const typedScalarBindingType = gen_ctrl.typedScalarBindingType;
const gen_union_emit = @import("gen_union_emit.zig");
// re-export gen_union_emit
const emitUnionValue = gen_union_emit.emitUnionValue;
const cloneUnionLayoutSubstituted = gen_union_emit.cloneUnionLayoutSubstituted;
const emitUnionStructPayloadForType = gen_union_emit.emitUnionStructPayloadForType;
const gen_struct = @import("gen_struct.zig");
// re-export gen_struct
const fieldReflectionLocalNamePrefix = gen_struct.fieldReflectionLocalNamePrefix;
const fieldVisibleFromTokens = gen_struct.fieldVisibleFromTokens;
const borrowedFieldMetaLocalSet = gen_struct.borrowedFieldMetaLocalSet;
pub const fieldGetLastUseMoveSource = gen_struct.fieldGetLastUseMoveSource;
const applyGuardLoopControlNarrowing = gen_struct.applyGuardLoopControlNarrowing;
const applyCollectGuardReturnNarrowing = gen_struct.applyCollectGuardReturnNarrowing;
// re-export gen_storage
const parseStorageType = gen_storage.parseStorageType;
const substituteStructFieldType = gen_storage.substituteStructFieldType;
pub const findFuncDeclForCallHead = gen_storage.findFuncDeclForCallHead;
const inferExprType = gen_storage.inferExprType;
const directManagedLastUseMoveSource = gen_storage.directManagedLastUseMoveSource;
const findCallbackBinding = gen_storage.findCallbackBinding;
const callbackBindingsHaveSameShape = gen_storage.callbackBindingsHaveSameShape;
const callArgMatchesParam = gen_storage.callArgMatchesParam;
const callArgsMatchVariadicTail = gen_storage.callArgsMatchVariadicTail;
pub const funcVariadicElemType = gen_storage.funcVariadicElemType;
const lambdaExprShape = gen_storage.lambdaExprShape;
const callbackBindingHasSameConcreteArg = gen_storage.callbackBindingHasSameConcreteArg;
const lambdaParamTypeName = gen_storage.lambdaParamTypeName;
const lambdaExplicitReturnType = gen_storage.lambdaExplicitReturnType;
const inferLambdaExprReturnType = gen_storage.inferLambdaExprReturnType;
const cloneLocalSet = gen_storage.cloneLocalSet;
const findCallbackRefFunc = gen_storage.findCallbackRefFunc;
const gen_ownership = @import("gen_ownership.zig");
const findTopLevelGuardLoopControl = gen_ownership.findTopLevelGuardLoopControl;

// re-export gen_host
const collectEnvHostImports = gen_host.collectEnvHostImports;
const collectEnvHostImportsFromModules = gen_host.collectEnvHostImportsFromModules;
const parseEnvHostImport = gen_host.parseEnvHostImport;
const findHostImport = gen_host.findHostImport;
const findHostImportForTokens = gen_host.findHostImportForTokens;
const isEnvHostImportStart = gen_host.isEnvHostImportStart;
const freeHostImports = gen_host.freeHostImports;
const hostCallArgsMatch = gen_host.hostCallArgsMatch;
const hostParamIsPtrLen = gen_host.hostParamIsPtrLen;
const hostArgCouldBeStoragePtrLenSyntax = gen_host.hostArgCouldBeStoragePtrLenSyntax;
// re-export gen_util helpers moved from lower
const moduleTokensEqual = gen_util.moduleTokensEqual;
pub const findStartFunc = gen_util.findStartFunc;
pub const findToken = gen_util.findToken;
const findTopLevelBlockOpen = gen_util.findTopLevelBlockOpen;
const findStmtEnd = gen_util.findStmtEnd;
const findTypeArgEnd = gen_util.findTypeArgEnd;
const stringLiteralArgLexeme = gen_util.stringLiteralArgLexeme;
const isStringLiteralArg = gen_util.isStringLiteralArg;
const isTypedBindingRhsCall = gen_util.isTypedBindingRhsCall;
const isBareHostCallStatement = gen_util.isBareHostCallStatement;
const moduleScopedSymbolName = gen_util.moduleScopedSymbolName;
const appendMangledTypeName = gen_util.appendMangledTypeName;
const isPublicTypeName = gen_util.isPublicTypeName;
const isErrorTypeName = gen_util.isErrorTypeName;
const isBaseIntTypeName = gen_util.isBaseIntTypeName;
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
const isCoreWasmScalar = gen_util.isCoreWasmScalar;
const isCoreIntegerScalar = gen_util.isCoreIntegerScalar;
const isCoreFloatScalar = gen_util.isCoreFloatScalar;
const isUserFuncDeclStart = gen_util.isUserFuncDeclStart;
const tokenTextEqualsCompact = gen_util.tokenTextEqualsCompact;
// re-export gen_import
const validateHostImportBuildUses = gen_import.validateHostImportBuildUses;
const validateReachableWasiHostImportBuildUses = gen_import.validateReachableWasiHostImportBuildUses;
const validateReachableWasiHostImportBuildUsesFromTests = gen_import.validateReachableWasiHostImportBuildUsesFromTests;
const validateReachableWasiHostImportStack = gen_import.validateReachableWasiHostImportStack;
const findRootModuleIndex = gen_import.findRootModuleIndex;
const wasiSourceForTokens = gen_import.wasiSourceForTokens;
const findWasiHostImportForTokens = gen_import.findWasiHostImportForTokens;
const hasReachVisit = gen_import.hasReachVisit;
const pushReachVisit = gen_import.pushReachVisit;
const collectStartBodyCalls = gen_import.collectStartBodyCalls;
const collectAllFunctionBodyCalls = gen_import.collectAllFunctionBodyCalls;
const collectTestBodyCalls = gen_import.collectTestBodyCalls;
const collectFunctionBodyCalls = gen_import.collectFunctionBodyCalls;
const collectCallNamesInRange = gen_import.collectCallNamesInRange;
const isLoopSourceSpecialCallName = gen_import.isLoopSourceSpecialCallName;
const findCodegenImportByAlias = gen_import.findCodegenImportByAlias;
const parseCodegenImport = gen_import.parseCodegenImport;
const importedScalarConst = gen_import.importedScalarConst;
const findImportedModuleIndexNoAlloc = gen_import.findImportedModuleIndexNoAlloc;
const moduleMatchesImportPath = gen_import.moduleMatchesImportPath;
const pathHasBaseAndFile = gen_import.pathHasBaseAndFile;
const localScalarConst = gen_import.localScalarConst;
const findImportedModuleIndex = gen_import.findImportedModuleIndex;
const findModuleByPath = gen_import.findModuleByPath;
const isValueEnumDeclStart = gen_import.isValueEnumDeclStart;
const isPayloadEnumDeclStart = gen_import.isPayloadEnumDeclStart;
const findValueEnumDecl = gen_import.findValueEnumDecl;
const findPayloadEnumDecl = gen_import.findPayloadEnumDecl;
const findValueEnumDeclLineByName = gen_import.findValueEnumDeclLineByName;
const findValueEnumDeclLineByBranch = gen_import.findValueEnumDeclLineByBranch;
const valueEnumLineHasBranch = gen_import.valueEnumLineHasBranch;
const collectStringDataForHostCalls = gen_import.collectStringDataForHostCalls;
const collectStringDataForWasiHostCalls = gen_import.collectStringDataForWasiHostCalls;
const collectStringDataForStorageLiterals = gen_import.collectStringDataForStorageLiterals;
const collectStringDataForStructFieldNames = gen_import.collectStringDataForStructFieldNames;
const hasBorrowedName = gen_import.hasBorrowedName;
const importedAliasContextForTokens = gen_import.importedAliasContextForTokens;
pub const callHeadAt = gen_import.callHeadAt;
const exprCallHead = gen_import.exprCallHead;
const callHeadHasTypeArgs = gen_import.callHeadHasTypeArgs;
// re-export gen_collect
const isPackManagedHandleLeaf = gen_collect.isPackManagedHandleLeaf;
pub const collectStructDecls = gen_collect.collectStructDecls;
const collectImportedStructDecls = gen_collect.collectImportedStructDecls;
const collectValueEnumDecls = gen_collect.collectValueEnumDecls;
const collectImportedValueEnumDecls = gen_collect.collectImportedValueEnumDecls;
const collectPayloadEnumDecls = gen_collect.collectPayloadEnumDecls;
const collectImportedPayloadEnumDecls = gen_collect.collectImportedPayloadEnumDecls;
pub const collectStructLayouts = gen_collect.collectStructLayouts;
const collectConcreteGenericStructLayouts = gen_collect.collectConcreteGenericStructLayouts;
const collectStoragePackLayoutsFromTokens = gen_collect.collectStoragePackLayoutsFromTokens;
const ensurePreopenDirTupleStoragePackLayout = gen_collect.ensurePreopenDirTupleStoragePackLayout;
const parseCodegenTypeExpr = gen_collect.parseCodegenTypeExpr;
const parseFuncParamTypeExpr = gen_collect.parseFuncParamTypeExpr;
const isTopLevelCommaAny = gen_collect.isTopLevelCommaAny;
pub const collectFuncDecls = gen_collect.collectFuncDecls;
const collectDirectImportedFuncDecls = gen_collect.collectDirectImportedFuncDecls;
const collectDirectImportedFuncDeclsFromTests = gen_collect.collectDirectImportedFuncDeclsFromTests;
const bindGenericType = gen_collect.bindGenericType;
pub const findGenericBinding = gen_collect.findGenericBinding;
const substituteGenericTypeOwned = gen_collect.substituteGenericTypeOwned;
const isTypeIdentStart = gen_collect.isTypeIdentStart;
const isTypeIdentPart = gen_collect.isTypeIdentPart;
const genericTypeArgsRange = gen_collect.genericTypeArgsRange;
const sameCallableSourceName = gen_collect.sameCallableSourceName;
const hasTypeParamName = gen_collect.hasTypeParamName;
const findFuncDecl = gen_collect.findFuncDecl;
pub const funcParamAbiType = gen_collect.funcParamAbiType;
const findStructDecl = gen_collect.findStructDecl;
const findStructLayout = gen_collect.findStructLayout;
const appendTupleLeafTypes = gen_collect.appendTupleLeafTypes;
// re-export gen_wasi_emit
const codegenTypesCompatible = gen_wasi_emit.codegenTypesCompatible;
pub fn emitWasiResourceDropCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResourceDropCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiListU8ResultCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiListU8ResultCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultUnitCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultUnitCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultDescriptorPathCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultDescriptorPathCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultOutputWriteCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultOutputWriteCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultDescriptorCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultDescriptorCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiDescriptorHandleArg(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    start_idx: usize,    end_idx: usize,    locals: *const LocalSet,    ctx: CodegenContext,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiDescriptorHandleArg(allocator, tokens, start_idx, end_idx, locals, ctx, out, emitExpr);
}

pub fn emitWasiResultLinkAtCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultLinkAtCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultFilesizeCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultFilesizeCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultU64StreamCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultU64StreamCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultReadCall(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultReadCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}

pub fn emitWasiResultListU8Call(    allocator: std.mem.Allocator,    tokens: []const lexer.Token,    args_start: usize,    args_end: usize,    locals: *const LocalSet,    ctx: CodegenContext,    import: WasiHostImport,    out: *std.ArrayList(u8)) CodegenError!bool {
    return gen_wasi_emit.emitWasiResultListU8Call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emitExpr);
}


fn installGenHooks() void {
    gen_hooks.install(gen_expr.emitExpr, gen_expr.emitExprWithMoveContext, gen_expr.emitUserFuncCallWithMoveContext);
    gen_hooks.installBody(gen_ctrl.emitBody);
    gen_hooks.installUnionValue(gen_union_emit.emitUnionValue);
    gen_hooks.installCollectBodyLocals(gen_expr.collectBodyLocals);
    gen_hooks.installCollectBodyLocalsWithMode(gen_expr.collectBodyLocalsWithMode);
    gen_hooks.installEmitMultiResultAssignment(gen_expr.emitMultiResultAssignment);
    gen_hooks.installEmitBareUserFuncCall(gen_expr.emitBareUserFuncCall);
    gen_hooks.installEmitBareUserFuncCallMove(gen_expr.emitBareUserFuncCallWithMoveContext);
    gen_hooks.installEmitUserFuncCallUnionBindingMove(gen_expr.emitUserFuncCallWithUnionBindingMove);
    gen_hooks.installEmitUnionStructPayloadForType(gen_union_emit.emitUnionStructPayloadForType);
    gen_hooks.installInferGenericCallUnionResult(inferGenericCallUnionResultLayout);
}

pub fn emitWat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph) ![]u8 {
    return emitWatWithOptions(allocator, program, tokens, module_graph, .{});
}

pub fn emitWatWithOptions(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
    options: EmitOptions) ![]u8 {
    installGenHooks();


    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        freeHostImports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try collectEnvHostImports(allocator, tokens, &host_imports);
    if (module_graph) |graph| {
        try collectEnvHostImportsFromModules(allocator, graph.modules, tokens, &host_imports);
    }
    try validateHostImportBuildUses(tokens, host_imports.items);

    var wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try collectWasiHostImportsFromModules(allocator, graph.modules, tokens, &wasi_imports);
    } else {
        try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &wasi_imports);
    }
    var entry_wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, entry_wasi_imports.items);
        entry_wasi_imports.deinit(allocator);
    }
    try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &entry_wasi_imports);
    try validateWasiHostImportBuildUses(tokens, entry_wasi_imports.items);
    if (module_graph) |graph| {
        try validateReachableWasiHostImportBuildUses(allocator, tokens, graph);
    }

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    try collectStringDataForHostCalls(allocator, tokens, host_imports.items, &string_data);
    try collectStringDataForWasiHostCalls(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, wasi_imports.items, &string_data);
    try collectStringDataForStorageLiterals(allocator, tokens, &string_data);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            const source = if (moduleTokensEqual(module.tokens, tokens))
                WASI_BINDING_ENTRY_SOURCE
            else
                module.path;
            try collectStringDataForHostCalls(allocator, module.tokens, host_imports.items, &string_data);
            try collectStringDataForWasiHostCalls(allocator, module.tokens, source, wasi_imports.items, &string_data);
            try collectStringDataForStorageLiterals(allocator, module.tokens, &string_data);
        }
    }

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        freeStructDecls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try collectStructDecls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collectImportedStructDecls(allocator, tokens, graph, &structs);
    }
    try collectStringDataForStructFieldNames(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        freeValueEnumDecls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collectValueEnumDecls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collectImportedValueEnumDecls(allocator, tokens, graph, &value_enums);
    }

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        freePayloadEnumDecls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try collectPayloadEnumDecls(allocator, tokens, &payload_enums);
    if (module_graph) |graph| {
        try collectImportedPayloadEnumDecls(allocator, tokens, graph, &payload_enums);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collectStructLayouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (findRootModuleIndex(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collectFuncDecls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collectDirectImportedFuncDecls(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
    }
    try collectGenericFuncInstancesForStart(
        allocator,
        tokens,
        structs.items,
        value_enums.items,
        payload_enums.items,
        struct_layouts.items,
        host_imports.items,
        wasi_imports.items,
        &string_data,
        if (module_graph) |graph| graph.modules else &.{},
        imported_alias_ctx,
        &functions,
    );
    try collectConcreteGenericStructLayouts(allocator, structs.items, functions.items, &struct_layouts);
    try collectStoragePackLayoutsFromTokens(allocator, tokens, structs.items, &struct_layouts);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            try collectStoragePackLayoutsFromTokens(allocator, module.tokens, structs.items, &struct_layouts);
        }
    }
    // Preopens always lower to [Tuple<Dir,text>] pack; ensure layout even if type text is only on host result sugar.
    try ensurePreopenDirTupleStoragePackLayout(allocator, wasi_imports.items, structs.items, &struct_layouts);
    try mangleOverloadedFunctionNames(allocator, &functions);

    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .value_enums = value_enums.items,
        .payload_enums = payload_enums.items,
        .struct_layouts = struct_layouts.items,
        .host_imports = host_imports.items,
        .wasi_imports = wasi_imports.items,
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| graph.modules else &.{},
        .imported_alias_ctx = imported_alias_ctx,
    };

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try component_metadata_wat.emitWasiBindings(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitWasiCoreImports(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitHostImports(allocator, &out, host_imports.items);
    try runtime_prelude_wat.emitStringDataMemory(allocator, &out, string_data.items.items, .{ .component_core = options.component_core });
    try runtime_prelude_wat.emitArcRuntimePrelude(allocator, &out, string_data.items.items, struct_layouts.items);
    try emitUserFuncs(allocator, ctx, &out);
    try emitStartFunc(allocator, tokens, ctx, &out);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

pub fn emitTestWat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph) ![]u8 {
    installGenHooks();


    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    const test_decls = try test_runner.collectTopLevelTests(allocator, tokens);
    defer allocator.free(test_decls);
    if (test_decls.len == 0) return error.NoTestDecl;

    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        freeHostImports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try collectEnvHostImports(allocator, tokens, &host_imports);
    if (module_graph) |graph| {
        try collectEnvHostImportsFromModules(allocator, graph.modules, tokens, &host_imports);
    }
    try validateHostImportBuildUses(tokens, host_imports.items);

    var wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try collectWasiHostImportsFromModules(allocator, graph.modules, tokens, &wasi_imports);
    } else {
        try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &wasi_imports);
    }
    var entry_wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, entry_wasi_imports.items);
        entry_wasi_imports.deinit(allocator);
    }
    try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &entry_wasi_imports);
    try validateWasiHostImportBuildUses(tokens, entry_wasi_imports.items);
    if (module_graph) |graph| {
        try validateReachableWasiHostImportBuildUsesFromTests(allocator, tokens, graph);
    }

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    try collectStringDataForHostCalls(allocator, tokens, host_imports.items, &string_data);
    try collectStringDataForWasiHostCalls(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, wasi_imports.items, &string_data);
    try collectStringDataForStorageLiterals(allocator, tokens, &string_data);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            const source = if (moduleTokensEqual(module.tokens, tokens))
                WASI_BINDING_ENTRY_SOURCE
            else
                module.path;
            try collectStringDataForHostCalls(allocator, module.tokens, host_imports.items, &string_data);
            try collectStringDataForWasiHostCalls(allocator, module.tokens, source, wasi_imports.items, &string_data);
            try collectStringDataForStorageLiterals(allocator, module.tokens, &string_data);
        }
    }

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        freeStructDecls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try collectStructDecls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collectImportedStructDecls(allocator, tokens, graph, &structs);
    }
    try collectStringDataForStructFieldNames(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        freeValueEnumDecls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collectValueEnumDecls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collectImportedValueEnumDecls(allocator, tokens, graph, &value_enums);
    }

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        freePayloadEnumDecls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try collectPayloadEnumDecls(allocator, tokens, &payload_enums);
    if (module_graph) |graph| {
        try collectImportedPayloadEnumDecls(allocator, tokens, graph, &payload_enums);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collectStructLayouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (findRootModuleIndex(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collectFuncDecls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collectDirectImportedFuncDeclsFromTests(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
    }
    try collectGenericFuncInstancesForTests(
        allocator,
        tokens,
        test_decls,
        structs.items,
        value_enums.items,
        payload_enums.items,
        struct_layouts.items,
        host_imports.items,
        wasi_imports.items,
        &string_data,
        if (module_graph) |graph| graph.modules else &.{},
        imported_alias_ctx,
        &functions,
    );
    try collectConcreteGenericStructLayouts(allocator, structs.items, functions.items, &struct_layouts);
    try collectStoragePackLayoutsFromTokens(allocator, tokens, structs.items, &struct_layouts);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            try collectStoragePackLayoutsFromTokens(allocator, module.tokens, structs.items, &struct_layouts);
        }
    }
    try ensurePreopenDirTupleStoragePackLayout(allocator, wasi_imports.items, structs.items, &struct_layouts);
    try mangleOverloadedFunctionNames(allocator, &functions);

    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .value_enums = value_enums.items,
        .payload_enums = payload_enums.items,
        .struct_layouts = struct_layouts.items,
        .host_imports = host_imports.items,
        .wasi_imports = wasi_imports.items,
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| graph.modules else &.{},
        .imported_alias_ctx = imported_alias_ctx,
    };

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try appendFmt(allocator, &out, "  ;; compiled_test_count={d}\n", .{test_decls.len});
    try component_metadata_wat.emitWasiBindings(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitWasiCoreImports(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitHostImports(allocator, &out, host_imports.items);
    try runtime_prelude_wat.emitStringDataMemory(allocator, &out, string_data.items.items, .{});
    try runtime_prelude_wat.emitArcRuntimePrelude(allocator, &out, string_data.items.items, struct_layouts.items);
    try emitUserFuncs(allocator, ctx, &out);
    try emitTestFuncs(allocator, tokens, test_decls, ctx, &out);
    try function_body_wat.emitTestStartFunc(allocator, &out, test_decls.len);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}















pub fn directManagedLastUseMoveSourceOrigin(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    target_source_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    defer_ctx: ?*const DeferContext,
) ?SourceOrigin {
    const source = directManagedLastUseMoveSource(tokens, start_idx, end_idx, body_end, target_source_name, locals, ctx, defer_ctx) orelse return null;
    return source.origin;
}



pub fn directManagedCallLastUseMoveSourceOrigin(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    move_ctx: CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?SourceOrigin {
    const source = directManagedCallLastUseMoveSource(tokens, start_idx, end_idx, move_ctx, locals, ctx) orelse return null;
    return source.origin;
}

pub fn directManagedUnionBindingCallMoveSourceOrigin(
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
) ?SourceOrigin {
    const source = directManagedUnionBindingCallMoveSource(tokens, start_idx, end_idx, args_end, stmt_end, body_end, allow_last_use_move, locals, ctx, defer_ctx) orelse return null;
    return source.origin;
}



const GenericTypeArgsRange = type_util.GenericTypeArgsRange;

pub fn mangleOverloadedFunctionNames(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(FuncDecl)) !void {
    for (functions.items, 0..) |func, idx| {
        if (func.is_generic_template) continue;
        if (!functionSourceNameHasMultipleConcreteDecls(functions.items, func.tokens, func.source_name)) continue;

        const next_name = try functionSignatureSymbolName(allocator, func);
        errdefer allocator.free(next_name);
        if (std.mem.eql(u8, next_name, func.name)) {
            allocator.free(next_name);
            continue;
        }
        if (functions.items[idx].owned_name) allocator.free(functions.items[idx].name);
        functions.items[idx].name = next_name;
        functions.items[idx].owned_name = true;
    }
}

pub fn functionSourceNameHasMultipleConcreteDecls(
    functions: []const FuncDecl,
    tokens: []const lexer.Token,
    source_name: []const u8) bool {
    var count: usize = 0;
    for (functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, source_name)) continue;
        count += 1;
        if (count > 1) return true;
    }
    return false;
}

pub fn functionSignatureSymbolName(
    allocator: std.mem.Allocator,
    func: FuncDecl) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, func.name);
    if (func.params.len == 0) {
        try out.appendSlice(allocator, "__nil");
        return out.toOwnedSlice(allocator);
    }
    for (func.params) |param| {
        try out.appendSlice(allocator, "__");
        if (param.variadic) try out.appendSlice(allocator, "rest_");
        try appendMangledTypeName(allocator, &out, param.ty);
    }
    return out.toOwnedSlice(allocator);
}

pub fn isCodegenImportAliasReachable(
    allocator: std.mem.Allocator,
    graph: *const imports.ModuleGraph,
    root_idx: usize,
    alias: []const u8) !bool {
    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectStartBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (visit.module_idx == root_idx and std.mem.eql(u8, visit.name, alias)) return true;
        if (hasReachVisit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        if (findCodegenImportByAlias(module.tokens, visit.name)) |import_ref| {
            if (findImportedModuleIndex(allocator, graph, visit.module_idx, import_ref)) |child_idx| {
                try pushReachVisit(allocator, &stack, .{
                    .module_idx = child_idx,
                    .name = import_ref.target,
                });
            }
            continue;
        }

        try collectFunctionBodyCalls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
    return false;
}








pub fn isTypedScalarBinding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) bool {
    return typedScalarBindingType(tokens, start_idx, end_idx, ctx) != null;
}



pub fn isStorageU8Type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const parsed = parseStorageType(tokens, start_idx, end_idx) orelse return false;
    return std.mem.eql(u8, parsed.elem_ty, "u8");
}











pub fn isPackTerminalLeafType(ty: []const u8, structs: []const StructDecl) bool {
    if (type_util.isTuplePackableLeafType(ty)) return true;
    return isPackManagedHandleLeaf(ty, structs);
}


/// Append terminal pack leaf types in order.
/// Pure-scalar struct fields expand nested; managed-struct slots stay one handle leaf (type name).
/// Append terminal pack leaf types in order.
/// Pure-scalar struct fields expand nested; managed-struct slots stay one handle leaf (type name).
pub fn appendStorePayloadOrTupleFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8) CodegenError!void {
    try payload_wat.appendStorePayloadOrTupleFromStack(allocator, out, elem_ty, base_local, indent);
}

pub fn appendLoadPayloadOrTupleToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8) CodegenError!void {
    try payload_wat.appendLoadPayloadOrTupleToStack(allocator, out, elem_ty, base_local, indent);
}


