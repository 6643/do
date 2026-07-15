const std = @import("std");
const backend_ir = @import("backend_ir.zig");
const component_metadata_wat = @import("component_metadata_wat.zig");
const function_body_wat = @import("function_body_wat.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const parser = @import("parser.zig");
const payload_wat = @import("wat_payload.zig");
const runtime_prelude_wat = @import("runtime_prelude_wat.zig");
const storage_wat = @import("wat_storage.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const context = @import("codegen_context.zig");

const LocalSet = context.LocalSet;
const ValueEnumBranch = model.ValueEnumBranch;
const PayloadEnumCase = model.PayloadEnumCase;
const ManagedFieldOffset = model.ManagedFieldOffset;
const TypedStructBinding = model.TypedStructBinding;
const InferredUnionBinding = model.InferredUnionBinding;
const TYPE_ID_STORAGE_U8 = constants.TYPE_ID_STORAGE_U8;
const TYPE_ID_STORAGE_MANAGED = constants.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_FIRST_STRUCT = constants.TYPE_ID_FIRST_STRUCT;
const STORAGE_PAYLOAD_HEADER_BYTES = constants.STORAGE_PAYLOAD_HEADER_BYTES;
const STORAGE_PUT_SOURCE_TMP_LOCAL = constants.STORAGE_PUT_SOURCE_TMP_LOCAL;
const VARIADIC_PACK_TMP_LOCAL = constants.VARIADIC_PACK_TMP_LOCAL;
const STORAGE_WRITE_INDEX_TMP_LOCAL = constants.STORAGE_WRITE_INDEX_TMP_LOCAL;
const STORAGE_WRITE_LEN_TMP_LOCAL = constants.STORAGE_WRITE_LEN_TMP_LOCAL;
const STORAGE_WRITE_NEXT_TMP_LOCAL = constants.STORAGE_WRITE_NEXT_TMP_LOCAL;
const STORAGE_WRITE_SCAN_TMP_LOCAL = constants.STORAGE_WRITE_SCAN_TMP_LOCAL;
const STORAGE_WRITE_TARGET_TMP_LOCAL = constants.STORAGE_WRITE_TARGET_TMP_LOCAL;
const TUPLE_PACK_BASE_TMP_LOCAL = constants.TUPLE_PACK_BASE_TMP_LOCAL;
const TUPLE_PACK_SPILL_I32 = constants.TUPLE_PACK_SPILL_I32;
const TUPLE_PACK_SPILL_I64 = constants.TUPLE_PACK_SPILL_I64;
const TUPLE_PACK_SPILL_F32 = constants.TUPLE_PACK_SPILL_F32;
const TUPLE_PACK_SPILL_F64 = constants.TUPLE_PACK_SPILL_F64;
const NUMERIC_SELECT_LEFT_TMP_I32 = constants.NUMERIC_SELECT_LEFT_TMP_I32;
const NUMERIC_SELECT_RIGHT_TMP_I32 = constants.NUMERIC_SELECT_RIGHT_TMP_I32;
const NUMERIC_SELECT_LEFT_TMP_I64 = constants.NUMERIC_SELECT_LEFT_TMP_I64;
const NUMERIC_SELECT_RIGHT_TMP_I64 = constants.NUMERIC_SELECT_RIGHT_TMP_I64;
const EMPTY_LOCAL_SET = context.EMPTY_LOCAL_SET;
const OwnedFuncTypeShape = model.OwnedFuncTypeShape;
const CallbackBindingKind = model.CallbackBindingKind;
const FuncResultParse = model.FuncResultParse;
const MultiResultLhsKind = model.MultiResultLhsKind;
const NO_RESULT_ITEMS = model.NO_RESULT_ITEMS;
const ParsedCodegenType = model.ParsedCodegenType;
const StructFieldAbiSlot = model.StructFieldAbiSlot;
const FuncBodyShape = model.FuncBodyShape;
const StructErrorResult = model.StructErrorResult;
const NilComparisonNarrowing = model.NilComparisonNarrowing;
const IsComparisonNarrowing = model.IsComparisonNarrowing;
const CodegenImportPrefix = model.CodegenImportPrefix;
const CodegenImportRef = model.CodegenImportRef;
const ImportedScalarConst = model.ImportedScalarConst;
const findStorageLocalOrigin = context.findStorageLocalOrigin;
const isCompilerLocalName = context.isCompilerLocalName;
const unionPayloadLocalName = context.unionPayloadLocalName;
const unionTagLocalName = context.unionTagLocalName;
const findUnionLocalExact = context.findUnionLocalExact;
const appendLoopSourceStorageLocal = context.appendLoopSourceStorageLocal;
const localNameMatches = context.localNameMatches;
const loopSourceLocalName = context.loopSourceLocalName;
const freeCallbackBindings = model.freeCallbackBindings;
const freeStructDecls = model.freeStructDecls;
const freeStructDecl = model.freeStructDecl;
const freeValueEnumDecls = model.freeValueEnumDecls;
const freePayloadEnumDecls = model.freePayloadEnumDecls;
const freeStructLayouts = model.freeStructLayouts;
const freeFuncParams = model.freeFuncParams;
const freeFuncDecls = model.freeFuncDecls;
const freeFuncResultItems = model.freeFuncResultItems;
const freeWasiHostImports = codegen_wasi_registry.free_wasi_host_imports;
const collectWasiHostImports = codegen_wasi_registry.collect_wasi_host_imports;
const collectWasiHostImportsFromModules = codegen_wasi_registry.collect_wasi_host_imports_from_modules;
const wasiLowering = codegen_wasi_registry.wasi_lowering;
const appendWasiImportSymbol = codegen_wasi_registry.append_wasi_import_symbol;
const ManagedPayloadBinding = codegen_storage_layout.ManagedPayloadBinding;
const ParsedStorageType = codegen_storage_layout.ParsedStorageType;
const Local = model.Local;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const EmitOptions = model.EmitOptions;
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
const DeferItem = context.DeferItem;
const DeferItemKind = context.DeferItemKind;
const LoopControl = context.LoopControl;
const CollectionLoopHeader = context.CollectionLoopHeader;
const RecvLoopHeader = context.RecvLoopHeader;
const FieldReflectionLoopHeader = context.FieldReflectionLoopHeader;
const FieldStaticValue = context.FieldStaticValue;
const FieldReflectionIfParts = context.FieldReflectionIfParts;
const FieldMetaLocal = model.FieldMetaLocal;
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
const StringData = model.StringData;
const SourceOrigin = model.SourceOrigin;
const ReachVisit = model.ReachVisit;
const MultiResultLhs = model.MultiResultLhs;
const NumericSelectTemps = model.NumericSelectTemps;
const SelfTailTco = context.SelfTailTco;
const ExprCallHead = model.ExprCallHead;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const STRUCT_LITERAL_TMP_LOCAL = constants.STRUCT_LITERAL_TMP_LOCAL;
const findLocalType = context.findLocalType;
const findLocalOrigin = context.findLocalOrigin;
const findStorageLocal = context.findStorageLocal;
const findStructLocal = context.findStructLocal;
const findUnionLocal = context.findUnionLocal;
const hasLocal = context.hasLocal;
const storageTypeNameForElem = context.storageTypeNameForElem;
const storageTypeNameForElemOwned = context.storageTypeNameForElemOwned;

const UnionLayout = codegen_union_layout.UnionLayout;
const UnionBranch = codegen_union_layout.UnionBranch;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const cloneUnionLayout = codegen_union_layout.clone_union_layout;
const unionLayoutsEqual = codegen_union_layout.union_layouts_equal;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const validateWasiHostImportBuildUses = codegen_wasi_registry.validate_wasi_host_import_build_uses;
const WASI_BINDING_ENTRY_SOURCE = codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE;

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
const decodeQuotedStringToken = codegen_tokens.decode_quoted_string_token;
const hasString = codegen_names.has_string;
const findTopLevelTypeSeparator = codegen_tokens.find_top_level_type_separator;
const findTopLevelTypeSeparatorFrom = codegen_tokens.find_top_level_type_separator_from;

const CallLastUseMoveContext = context.CallLastUseMoveContext;
const gen_host = @import("gen_host.zig");
const gen_import = @import("gen_import.zig");
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_collect_declarations = @import("codegen_collect_declarations.zig");
const codegen_collect_body = @import("codegen_collect_body.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const tuple_element_type_at = codegen_emit_wasi.tuple_element_type_at;
const tuple_scalar_leaf_storage_byte_width_ctx = codegen_emit_wasi.tuple_scalar_leaf_storage_byte_width_ctx;
const find_storage_primitive_local = codegen_emit_wasi.find_storage_primitive_local;
const is_storage_type_name = codegen_emit_wasi.is_storage_type_name;
const tuple_arity = codegen_emit_wasi.tuple_arity;
const is_tuple_type_name = codegen_emit_wasi.is_tuple_type_name;
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_emit_storage_values = @import("codegen_emit_storage_values.zig");
const codegen_emit_storage_operations = @import("codegen_emit_storage_operations.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_emit_expression = @import("codegen_emit_expression.zig");
const codegen_emit_call = @import("codegen_emit_call.zig");
const gen_generic = @import("gen_generic.zig");
const collect_body_locals_with_mode = codegen_collect_body.collect_body_locals_with_mode;
// Re-export expression and call emit entry points.
const emit_start_func = codegen_emit_expression.emit_start_func;
pub const emit_scalar_numeric_start_with_backend_ir = codegen_emit_expression.emit_scalar_numeric_start_with_backend_ir;
const emit_test_funcs = codegen_emit_expression.emit_test_funcs;
const emit_user_funcs = codegen_emit_expression.emit_user_funcs;

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

pub fn collect_body_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) anyerror!void {
    installGenHooks();
    return codegen_collect_body.collect_body_locals(allocator, tokens, start_idx, end_idx, ctx, out);
}
const direct_managed_call_last_use_move_source = codegen_emit_call.direct_managed_call_last_use_move_source;
const direct_managed_union_binding_call_move_source = codegen_emit_call.direct_managed_union_binding_call_move_source;
const emit_multi_result_assignment = codegen_emit_call.emit_multi_result_assignment;
pub fn emit_expr(
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
    return codegen_emit_expression.emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, out);
}
pub fn emit_expr_with_move_context(
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
    return codegen_emit_expression.emit_expr_with_move_context(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, move_ctx, out);
}
const emit_bare_user_func_call = codegen_emit_call.emit_bare_user_func_call;
const emit_bare_user_func_call_with_move_context = codegen_emit_call.emit_bare_user_func_call_with_move_context;
const append_func_param_locals = codegen_emit_call.append_func_param_locals;
const func_has_callback_params = codegen_emit_call.func_has_callback_params;
const emit_user_func_call_with_move_context = codegen_emit_call.emit_user_func_call_with_move_context;
const emit_user_func_call_with_union_binding_move = codegen_emit_call.emit_user_func_call_with_union_binding_move;
const codegen_emit_control = @import("codegen_emit_control.zig");
// re-export codegen_emit_control
const field_reflection_loop_header = codegen_emit_control.field_reflection_loop_header;
const emit_body = codegen_emit_control.emit_body;
const append_condition_narrowing_for_branch = codegen_emit_control.append_condition_narrowing_for_branch;
const typed_scalar_binding_type = codegen_emit_control.typed_scalar_binding_type;
const codegen_emit_union = @import("codegen_emit_union.zig");
// re-export codegen_emit_union
const emit_union_value = codegen_emit_union.emit_union_value;
const clone_union_layout_substituted = codegen_emit_union.clone_union_layout_substituted;
const emit_union_struct_payload_for_type = codegen_emit_union.emit_union_struct_payload_for_type;
const codegen_emit_struct = @import("codegen_emit_struct.zig");
const codegen_emit_struct_fields = @import("codegen_emit_struct_fields.zig");
// re-export codegen_emit_struct
const field_reflection_local_name_prefix = codegen_emit_struct_fields.field_reflection_local_name_prefix;
const field_visible_from_tokens = codegen_emit_struct_fields.field_visible_from_tokens;
const borrowed_field_meta_local_set = codegen_emit_struct_fields.borrowed_field_meta_local_set;
pub const field_get_last_use_move_source = codegen_emit_struct_fields.field_get_last_use_move_source;
const apply_guard_loop_control_narrowing = codegen_emit_struct_fields.apply_guard_loop_control_narrowing;
const apply_collect_guard_return_narrowing = codegen_emit_struct_fields.apply_collect_guard_return_narrowing;
// re-export codegen_emit_storage_values
const parse_storage_type = codegen_storage_layout.parse_storage_type;
const substitute_struct_field_type = codegen_storage_layout.substitute_struct_field_type;
pub const find_func_decl_for_call_head = codegen_storage_layout.find_func_decl_for_call_head;
const infer_expr_type = codegen_storage_layout.infer_expr_type;
const direct_managed_last_use_move_source = codegen_emit_storage_values.direct_managed_last_use_move_source;
const find_callback_binding = codegen_storage_layout.find_callback_binding;
const callback_bindings_have_same_shape = codegen_storage_layout.callback_bindings_have_same_shape;
const call_arg_matches_param = codegen_storage_layout.call_arg_matches_param;
const call_args_match_variadic_tail = codegen_storage_layout.call_args_match_variadic_tail;
pub const func_variadic_elem_type = codegen_storage_layout.func_variadic_elem_type;
const lambda_expr_shape = codegen_storage_layout.lambda_expr_shape;
const callback_binding_has_same_concrete_arg = codegen_storage_layout.callback_binding_has_same_concrete_arg;
const lambda_param_type_name = codegen_storage_layout.lambda_param_type_name;
const lambda_explicit_return_type = codegen_storage_layout.lambda_explicit_return_type;
const infer_lambda_expr_return_type = codegen_storage_layout.infer_lambda_expr_return_type;
const clone_local_set = codegen_storage_layout.clone_local_set;
const find_callback_ref_func = codegen_storage_layout.find_callback_ref_func;
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
// Re-export token and name helpers used by lower-level tests.
const moduleTokensEqual = codegen_tokens.module_tokens_equal;
pub const findStartFunc = codegen_tokens.find_start_func;
pub const findToken = codegen_tokens.find_token;
const findTopLevelBlockOpen = codegen_tokens.find_top_level_block_open;
const findStmtEnd = codegen_tokens.find_stmt_end;
const findTypeArgEnd = codegen_tokens.find_type_arg_end;
const stringLiteralArgLexeme = codegen_tokens.string_literal_arg_lexeme;
const isStringLiteralArg = codegen_tokens.is_string_literal_arg;
const isTypedBindingRhsCall = codegen_tokens.is_typed_binding_rhs_call;
const isBareHostCallStatement = codegen_tokens.is_bare_host_call_statement;
const moduleScopedSymbolName = codegen_names.module_scoped_symbol_name;
const appendMangledTypeName = codegen_names.append_mangled_type_name;
const isPublicTypeName = codegen_names.is_public_type_name;
const isErrorTypeName = codegen_names.is_error_type_name;
const isBaseIntTypeName = codegen_names.is_base_int_type_name;
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
const isCoreWasmScalar = codegen_names.is_core_wasm_scalar;
const isCoreIntegerScalar = codegen_names.is_core_integer_scalar;
const isCoreFloatScalar = codegen_names.is_core_float_scalar;
const isUserFuncDeclStart = codegen_tokens.is_user_func_decl_start;
const tokenTextEqualsCompact = codegen_tokens.token_text_equals_compact;
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
// Collection owner aliases used by the pipeline.
const is_pack_managed_handle_leaf = codegen_collect_structs.is_pack_managed_handle_leaf;
const collect_struct_decls = codegen_collect_structs.collect_struct_decls;
const collect_imported_struct_decls = codegen_collect_structs.collect_imported_struct_decls;
const collect_value_enum_decls = codegen_collect_declarations.collect_value_enum_decls;
const collect_imported_value_enum_decls = codegen_collect_declarations.collect_imported_value_enum_decls;
const collect_payload_enum_decls = codegen_collect_declarations.collect_payload_enum_decls;
const collect_imported_payload_enum_decls = codegen_collect_declarations.collect_imported_payload_enum_decls;
const collect_struct_layouts = codegen_collect_structs.collect_struct_layouts;
const collect_concrete_generic_struct_layouts = codegen_collect_structs.collect_concrete_generic_struct_layouts;
const collect_storage_pack_layouts_from_tokens = codegen_collect_structs.collect_storage_pack_layouts_from_tokens;
const ensure_preopen_dir_tuple_storage_pack_layout = codegen_collect_structs.ensure_preopen_dir_tuple_storage_pack_layout;
const parseCodegenTypeExpr = gen_collect_util.parseCodegenTypeExpr;
const parse_func_param_type_expr = codegen_collect_functions.parse_func_param_type_expr;
const is_top_level_comma_any = codegen_collect_functions.is_top_level_comma_any;
const collect_func_decls = codegen_collect_functions.collect_func_decls;
const collect_direct_imported_func_decls = codegen_collect_functions.collect_direct_imported_func_decls;
const collect_direct_imported_func_decls_from_tests = codegen_collect_functions.collect_direct_imported_func_decls_from_tests;
const bindGenericType = gen_collect_util.bindGenericType;
pub const findGenericBinding = gen_collect_util.findGenericBinding;
const substituteGenericTypeOwned = gen_collect_util.substituteGenericTypeOwned;
const isTypeIdentStart = gen_collect_util.isTypeIdentStart;
const isTypeIdentPart = gen_collect_util.isTypeIdentPart;
const genericTypeArgsRange = gen_collect_util.genericTypeArgsRange;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const hasTypeParamName = gen_collect_util.hasTypeParamName;
const find_func_decl = codegen_collect_functions.find_func_decl;
pub const funcParamAbiType = gen_collect_util.funcParamAbiType;
const findStructDecl = gen_collect_util.findStructDecl;
const findStructLayout = gen_collect_util.findStructLayout;
const appendTupleLeafTypes = gen_collect_util.appendTupleLeafTypes;
// re-export codegen_emit_wasi
const codegen_types_compatible = codegen_emit_wasi.codegen_types_compatible;
pub fn emitWasiResourceDropCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_resource_drop_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiListU8ResultCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_list_u8_result_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultUnitCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_unit_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultDescriptorPathCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_descriptor_path_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultOutputWriteCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_output_write_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultDescriptorCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_descriptor_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiDescriptorHandleArg(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_descriptor_handle_arg(allocator, tokens, start_idx, end_idx, locals, ctx, out, emit_expr);
}

pub fn emitWasiResultLinkAtCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_link_at_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultFilesizeCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_filesize_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultU64StreamCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_u64_stream_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultReadCall(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_read_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emitWasiResultListU8Call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_list_u8_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

fn installGenHooks() void {
    codegen_callbacks.install(codegen_emit_expression.emit_expr, codegen_emit_expression.emit_expr_with_move_context, codegen_emit_call.emit_user_func_call_with_move_context);
    codegen_callbacks.install_body(codegen_emit_control.emit_body);
    codegen_callbacks.install_union_value(codegen_emit_union.emit_union_value);
    codegen_callbacks.install_collect_body_locals(codegen_collect_body.collect_body_locals);
    codegen_callbacks.install_collect_body_locals_with_mode(codegen_collect_body.collect_body_locals_with_mode);
    codegen_callbacks.install_emit_multi_result_assignment(codegen_emit_call.emit_multi_result_assignment);
    codegen_callbacks.install_emit_bare_user_func_call(codegen_emit_call.emit_bare_user_func_call);
    codegen_callbacks.install_emit_bare_user_func_call_move(codegen_emit_call.emit_bare_user_func_call_with_move_context);
    codegen_callbacks.install_emit_user_func_call_union_binding_move(codegen_emit_call.emit_user_func_call_with_union_binding_move);
    codegen_callbacks.install_emit_union_struct_payload_for_type(codegen_emit_union.emit_union_struct_payload_for_type);
    codegen_callbacks.install_infer_generic_call_union_result(inferGenericCallUnionResultLayout);
}

pub fn emitWat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
    return emitWatWithOptions(allocator, program, tokens, module_graph, .{});
}

pub fn emitWatWithOptions(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph, options: EmitOptions) ![]u8 {
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
    try collect_struct_decls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collect_imported_struct_decls(allocator, tokens, graph, &structs);
    }
    try collectStringDataForStructFieldNames(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        freeValueEnumDecls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collect_value_enum_decls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collect_imported_value_enum_decls(allocator, tokens, graph, &value_enums);
    }

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        freePayloadEnumDecls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try collect_payload_enum_decls(allocator, tokens, &payload_enums);
    if (module_graph) |graph| {
        try collect_imported_payload_enum_decls(allocator, tokens, graph, &payload_enums);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collect_struct_layouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (findRootModuleIndex(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collect_func_decls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collect_direct_imported_func_decls(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
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
    try collect_concrete_generic_struct_layouts(allocator, structs.items, functions.items, &struct_layouts);
    try collect_storage_pack_layouts_from_tokens(allocator, tokens, structs.items, &struct_layouts);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            try collect_storage_pack_layouts_from_tokens(allocator, module.tokens, structs.items, &struct_layouts);
        }
    }
    // Preopens always lower to [Tuple<Dir,text>] pack; ensure layout even if type text is only on host result sugar.
    try ensure_preopen_dir_tuple_storage_pack_layout(allocator, wasi_imports.items, structs.items, &struct_layouts);
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
    try emit_user_funcs(allocator, ctx, &out);
    try emit_start_func(allocator, tokens, ctx, &out);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

pub fn emitTestWat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
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
    try collect_struct_decls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collect_imported_struct_decls(allocator, tokens, graph, &structs);
    }
    try collectStringDataForStructFieldNames(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        freeValueEnumDecls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collect_value_enum_decls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collect_imported_value_enum_decls(allocator, tokens, graph, &value_enums);
    }

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        freePayloadEnumDecls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try collect_payload_enum_decls(allocator, tokens, &payload_enums);
    if (module_graph) |graph| {
        try collect_imported_payload_enum_decls(allocator, tokens, graph, &payload_enums);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collect_struct_layouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (findRootModuleIndex(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collect_func_decls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collect_direct_imported_func_decls_from_tests(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
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
    try collect_concrete_generic_struct_layouts(allocator, structs.items, functions.items, &struct_layouts);
    try collect_storage_pack_layouts_from_tokens(allocator, tokens, structs.items, &struct_layouts);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            try collect_storage_pack_layouts_from_tokens(allocator, module.tokens, structs.items, &struct_layouts);
        }
    }
    try ensure_preopen_dir_tuple_storage_pack_layout(allocator, wasi_imports.items, structs.items, &struct_layouts);
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
    try emit_user_funcs(allocator, ctx, &out);
    try emit_test_funcs(allocator, tokens, test_decls, ctx, &out);
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
    const source = direct_managed_last_use_move_source(tokens, start_idx, end_idx, body_end, target_source_name, locals, ctx, defer_ctx) orelse return null;
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
    const source = direct_managed_call_last_use_move_source(tokens, start_idx, end_idx, move_ctx, locals, ctx) orelse return null;
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
    const source = direct_managed_union_binding_call_move_source(tokens, start_idx, end_idx, args_end, stmt_end, body_end, allow_last_use_move, locals, ctx, defer_ctx) orelse return null;
    return source.origin;
}

const GenericTypeArgsRange = type_util.GenericTypeArgsRange;

pub fn mangleOverloadedFunctionNames(allocator: std.mem.Allocator, functions: *std.ArrayList(FuncDecl)) !void {
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

pub fn functionSourceNameHasMultipleConcreteDecls(functions: []const FuncDecl, tokens: []const lexer.Token, source_name: []const u8) bool {
    var count: usize = 0;
    for (functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!same_callable_source_name(func.source_name, source_name)) continue;
        count += 1;
        if (count > 1) return true;
    }
    return false;
}

pub fn functionSignatureSymbolName(allocator: std.mem.Allocator, func: FuncDecl) ![]u8 {
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

pub fn isCodegenImportAliasReachable(allocator: std.mem.Allocator, graph: *const imports.ModuleGraph, root_idx: usize, alias: []const u8) !bool {
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
    return typed_scalar_binding_type(tokens, start_idx, end_idx, ctx) != null;
}

pub fn isStorageU8Type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const parsed = parse_storage_type(tokens, start_idx, end_idx) orelse return false;
    return std.mem.eql(u8, parsed.elem_ty, "u8");
}

pub fn isPackTerminalLeafType(ty: []const u8, structs: []const StructDecl) bool {
    if (type_util.isTuplePackableLeafType(ty)) return true;
    return is_pack_managed_handle_leaf(ty, structs);
}

/// Append terminal pack leaf types in order.
/// Pure-scalar struct fields expand nested; managed-struct slots stay one handle leaf (type name).
/// Append terminal pack leaf types in order.
/// Pure-scalar struct fields expand nested; managed-struct slots stay one handle leaf (type name).
pub fn appendStorePayloadOrTupleFromStack(allocator: std.mem.Allocator, out: *std.ArrayList(u8), elem_ty: []const u8, base_local: []const u8, indent: []const u8) CodegenError!void {
    try payload_wat.append_store_payload_or_tuple_from_stack(allocator, out, elem_ty, base_local, indent);
}

pub fn appendLoadPayloadOrTupleToStack(allocator: std.mem.Allocator, out: *std.ArrayList(u8), elem_ty: []const u8, base_local: []const u8, indent: []const u8) CodegenError!void {
    try payload_wat.append_load_payload_or_tuple_to_stack(allocator, out, elem_ty, base_local, indent);
}
