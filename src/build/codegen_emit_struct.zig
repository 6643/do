//! Struct construction and aggregate value emission.

const struct_fields = @import("codegen_emit_struct_fields.zig");
const append_managed_struct_field_ptr = struct_fields.append_managed_struct_field_ptr;
const emit_managed_struct_field_set = struct_fields.emit_managed_struct_field_set;
const emit_struct_field_local_set = struct_fields.emit_struct_field_local_set;
const emit_struct_field_value = struct_fields.emit_struct_field_value;
const emit_struct_fields_from_local = struct_fields.emit_struct_fields_from_local;
const emit_zero_value_for_type = struct_fields.emit_zero_value_for_type;
const inferred_struct_binding = struct_fields.inferred_struct_binding;
const is_managed_struct_field = struct_fields.is_managed_struct_field;
const typed_struct_binding = struct_fields.typed_struct_binding;

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
const IsComparisonNarrowing = model.IsComparisonNarrowing;
const NilComparisonNarrowing = model.NilComparisonNarrowing;
const TypedStructBinding = model.TypedStructBinding;
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const gen_import = @import("gen_import.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const gen_ownership = @import("gen_ownership.zig");
const findTopLevelGuardLoopControl = gen_ownership.findTopLevelGuardLoopControl;
const labelForLoopStart = gen_ownership.labelForLoopStart;
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

const codegen_emit_storage_values = @import("codegen_emit_storage_values.zig");
const emit_storage_binding = codegen_emit_storage_values.emit_storage_binding;
const emit_storage_handle_assignment_expr = codegen_emit_storage_values.emit_storage_handle_assignment_expr;
const emit_tuple_binding = codegen_emit_storage_values.emit_tuple_binding;
const emit_storage_assignment = codegen_emit_storage_values.emit_storage_assignment;
const stmt_contains_storage_agg_literal = codegen_emit_storage_values.stmt_contains_storage_agg_literal;
const emit_storage_agg_return_value = codegen_emit_storage_values.emit_storage_agg_return_value;
const emitTupleReturnLocal = codegen_emit_storage_values.emitTupleReturnLocal;
const emit_tuple_return_expr = codegen_emit_storage_values.emit_tuple_return_expr;
const emit_storage_u8_string_literal = codegen_emit_storage_values.emit_storage_u8_string_literal;
const emit_storage_u8_string_literal_value = codegen_emit_storage_values.emit_storage_u8_string_literal_value;
const emit_storage_u8_raw_string_value = codegen_emit_storage_values.emit_storage_u8_raw_string_value;
const emit_storage_u8_string_literal_into_local = codegen_emit_storage_values.emit_storage_u8_string_literal_into_local;
const emit_storage_agg_literal = codegen_emit_storage_values.emit_storage_agg_literal;
const isStorageAggLiteralExpr = codegen_emit_storage_values.isStorageAggLiteralExpr;
const count_agg_literal_items = codegen_emit_storage_values.count_agg_literal_items;
const emit_storage_payload_ptr = codegen_emit_storage_values.emit_storage_payload_ptr;
const emitStorageLenPtrWithIndent = codegen_emit_storage_values.emitStorageLenPtrWithIndent;
const emitStorageCapPtr = codegen_emit_storage_values.emitStorageCapPtr;
const emitStorageCapPtrWithIndent = codegen_emit_storage_values.emitStorageCapPtrWithIndent;
const emit_storage_payload_ptr_with_indent = codegen_emit_storage_values.emit_storage_payload_ptr_with_indent;
const emitTupleLocalSet = codegen_emit_storage_values.emitTupleLocalSet;
const emitTupleLocalGet = codegen_emit_storage_values.emitTupleLocalGet;
const emitTupleGetBinding = codegen_emit_storage_values.emitTupleGetBinding;
const emit_storage_content_comparison_call = codegen_emit_storage_values.emit_storage_content_comparison_call;
const emit_managed_payload_storage_content_comparison_call = codegen_emit_storage_values.emit_managed_payload_storage_content_comparison_call;
const inferStorageContentComparisonType = codegen_emit_storage_values.inferStorageContentComparisonType;
const storageContentArgCompatible = codegen_emit_storage_values.storageContentArgCompatible;
const isManagedPayloadComparableType = codegen_emit_storage_values.isManagedPayloadComparableType;
const emit_storage_ptr_len_host_arg = codegen_emit_storage_values.emit_storage_ptr_len_host_arg;
const emit_tuple_expr = codegen_emit_storage_values.emit_tuple_expr;
const storageBindingElemType = codegen_emit_storage_values.storageBindingElemType;
const managedPayloadBinding = codegen_emit_storage_values.managedPayloadBinding;
const parseStorageType = codegen_emit_storage_values.parseStorageType;
const emitStorageBoundsCheck = codegen_emit_storage_values.emitStorageBoundsCheck;
const emitStorageWriteExpr = codegen_emit_storage_values.emitStorageWriteExpr;
const emitStorageSetExpr = codegen_emit_storage_values.emitStorageSetExpr;
const emitStoragePutCall = codegen_emit_storage_values.emitStoragePutCall;
const emitStoragePutExpr = codegen_emit_storage_values.emitStoragePutExpr;
const emitStoragePutSpreadCall = codegen_emit_storage_values.emitStoragePutSpreadCall;
const emitStorageSetScalarCall = codegen_emit_storage_values.emitStorageSetScalarCall;
const emitStoragePutSpreadScalarElement = codegen_emit_storage_values.emitStoragePutSpreadScalarElement;
const emitStoragePutScalarCall = codegen_emit_storage_values.emitStoragePutScalarCall;
const emitStorageCloneCurrentLen = codegen_emit_storage_values.emitStorageCloneCurrentLen;
const emitStorageCloneCurrentLenForElem = codegen_emit_storage_values.emitStorageCloneCurrentLenForElem;
const emitStorageCloneManagedCurrentLen = codegen_emit_storage_values.emitStorageCloneManagedCurrentLen;
const emitStorageCloneManagedWithLenLocal = codegen_emit_storage_values.emitStorageCloneManagedWithLenLocal;
const emitStorageIncCopiedManagedElements = codegen_emit_storage_values.emitStorageIncCopiedManagedElements;
const emitStorageCloneWithLenLocal = codegen_emit_storage_values.emitStorageCloneWithLenLocal;
const emitStorageCloneWithLenLocalForElem = codegen_emit_storage_values.emitStorageCloneWithLenLocalForElem;
const emitStorageCloneWithLenLocalTyped = codegen_emit_storage_values.emitStorageCloneWithLenLocalTyped;
const emitStorageIncCopiedPackElements = codegen_emit_storage_values.emitStorageIncCopiedPackElements;
const emitStorageElementPtrFromLocal = codegen_emit_storage_values.emitStorageElementPtrFromLocal;
const emitStorageElementPtrFromLocalWithIndent = codegen_emit_storage_values.emitStorageElementPtrFromLocalWithIndent;
const emitStorageAliasProtect = codegen_emit_storage_values.emitStorageAliasProtect;
const emitStorageAliasRelease = codegen_emit_storage_values.emitStorageAliasRelease;
const emit_empty_storage_u8_value = codegen_emit_storage_values.emit_empty_storage_u8_value;
const emit_empty_storage_for_elem_type = codegen_emit_storage_values.emit_empty_storage_for_elem_type;
const storageElementByteWidthForType = codegen_emit_storage_values.storageElementByteWidthForType;
const tuplePackSpillLocal = codegen_emit_storage_values.tuplePackSpillLocal;
const appendStoreTupleScalarLeavesFromStack = codegen_emit_storage_values.appendStoreTupleScalarLeavesFromStack;
const appendStoreTupleScalarLeavesFromStackCtx = codegen_emit_storage_values.appendStoreTupleScalarLeavesFromStackCtx;
const appendStoreTupleLeavesOwningFromStack = codegen_emit_storage_values.appendStoreTupleLeavesOwningFromStack;
const appendStoreTupleLeavesOwningFromStackCtx = codegen_emit_storage_values.appendStoreTupleLeavesOwningFromStackCtx;
const appendIncManagedTupleLeavesOnStackCtx = codegen_emit_storage_values.appendIncManagedTupleLeavesOnStackCtx;
const appendLoadTupleScalarLeavesToStack = codegen_emit_storage_values.appendLoadTupleScalarLeavesToStack;
const appendLoadTupleScalarLeavesToStackCtx = codegen_emit_storage_values.appendLoadTupleScalarLeavesToStackCtx;
const appendLoadTupleLeavesOwningToStack = codegen_emit_storage_values.appendLoadTupleLeavesOwningToStack;
const appendLoadTupleLeavesOwningToStackCtx = codegen_emit_storage_values.appendLoadTupleLeavesOwningToStackCtx;
const appendLoadTupleElementFromPackedBaseCtx = codegen_emit_storage_values.appendLoadTupleElementFromPackedBaseCtx;
const appendLoadTupleLeafTypesOfStructToStack = codegen_emit_storage_values.appendLoadTupleLeafTypesOfStructToStack;
const appendLoadTupleElementOwningFromPackedBase = codegen_emit_storage_values.appendLoadTupleElementOwningFromPackedBase;
const emitIncManagedTupleLeavesAtBase = codegen_emit_storage_values.emitIncManagedTupleLeavesAtBase;
const emitDecManagedTupleLeavesAtBase = codegen_emit_storage_values.emitDecManagedTupleLeavesAtBase;
const emit_number_const = codegen_emit_storage_values.emit_number_const;
const appendStoreForPayloadType = codegen_emit_storage_values.appendStoreForPayloadType;
const appendStoreForPayloadTypeWithIndent = codegen_emit_storage_values.appendStoreForPayloadTypeWithIndent;
const appendLoadForPayloadTypeWithIndent = codegen_emit_storage_values.appendLoadForPayloadTypeWithIndent;
const emit_tuple_field_path_get_call = codegen_emit_storage_values.emit_tuple_field_path_get_call;
const emitPureScalarStructLocalSet = codegen_emit_storage_values.emitPureScalarStructLocalSet;
const emitPureScalarStructLocalGet = codegen_emit_storage_values.emitPureScalarStructLocalGet;
const singleTupleResultItem = codegen_emit_storage_values.singleTupleResultItem;
const isDirectManagedLocalExpr = codegen_emit_storage_values.isDirectManagedLocalExpr;
const storagePackLayoutForElem = codegen_emit_storage_values.storagePackLayoutForElem;
const tupleElementPackOffsetWithStructs = codegen_emit_storage_values.tupleElementPackOffsetWithStructs;
const tupleFieldPathType = codegen_emit_storage_values.tupleFieldPathType;
const find_struct_literal_field = codegen_emit_storage_values.find_struct_literal_field;
const substituteStructFieldType = codegen_emit_storage_values.substituteStructFieldType;
const is_struct_literal_rhs = codegen_emit_storage_values.is_struct_literal_rhs;
const emitReplaceStoragePutSourceTmp = codegen_emit_storage_values.emitReplaceStoragePutSourceTmp;
const directManagedLocalExprName = codegen_emit_storage_values.directManagedLocalExprName;
const emitOverwriteReleaseManagedLocal = codegen_emit_storage_values.emitOverwriteReleaseManagedLocal;
const findLocalFieldType = codegen_emit_storage_values.findLocalFieldType;
const tupleGetElementInfo = codegen_emit_storage_values.tupleGetElementInfo;
const findFuncDeclForCallHead = codegen_emit_storage_values.findFuncDeclForCallHead;
const inferExprType = codegen_emit_storage_values.inferExprType;
const find_struct_literal_field_end = codegen_emit_storage_values.find_struct_literal_field_end;
const findStructFieldType = codegen_emit_storage_values.findStructFieldType;
const localFieldNameMatches = codegen_emit_storage_values.localFieldNameMatches;
const direct_managed_last_use_move_source = codegen_emit_storage_values.direct_managed_last_use_move_source;
const structLiteralOpenRhs = codegen_emit_storage_values.structLiteralOpenRhs;
const unionPayloadLocalNameFromLocals = codegen_emit_storage_values.unionPayloadLocalNameFromLocals;
const substituteGenericType = codegen_emit_storage_values.substituteGenericType;
const isUnionPayloadLocalName = codegen_emit_storage_values.isUnionPayloadLocalName;
const findCallbackCallArg = codegen_emit_storage_values.findCallbackCallArg;
const appendTupleLocalFieldsBorrowed = codegen_emit_storage_values.appendTupleLocalFieldsBorrowed;
const findFuncDeclForCall = codegen_emit_storage_values.findFuncDeclForCall;
const findLocalName = codegen_emit_storage_values.findLocalName;
const emitStorageSetCall = codegen_emit_storage_values.emitStorageSetCall;
const emitStoragePutOneCall = codegen_emit_storage_values.emitStoragePutOneCall;
const callExplicitTypeArgsMatchBindings = codegen_emit_storage_values.callExplicitTypeArgsMatchBindings;
const callArgsMatchFuncParams = codegen_emit_storage_values.callArgsMatchFuncParams;
const has_registered_defer_stmt = codegen_emit_storage_values.has_registered_defer_stmt;
const appendBorrowedLocalField = codegen_emit_storage_values.appendBorrowedLocalField;
const token_range_uses_ident = codegen_emit_storage_values.token_range_uses_ident;
const shouldInferBoolSpecialCall = codegen_emit_storage_values.shouldInferBoolSpecialCall;
const is_defer_stmt = codegen_emit_storage_values.is_defer_stmt;
const callArgMatchesCallbackShape = codegen_emit_storage_values.callArgMatchesCallbackShape;
const emitStorageSetManagedCall = codegen_emit_storage_values.emitStorageSetManagedCall;
const emitStoragePutManagedCall = codegen_emit_storage_values.emitStoragePutManagedCall;
const emitManagedStorageValue = codegen_emit_storage_values.emitManagedStorageValue;
const inferScalarAsCallType = codegen_emit_storage_values.inferScalarAsCallType;
const findCallbackBinding = codegen_emit_storage_values.findCallbackBinding;
const scalarAsTargetType = codegen_emit_storage_values.scalarAsTargetType;
const callArgMatchesConcreteCallbackBinding = codegen_emit_storage_values.callArgMatchesConcreteCallbackBinding;
const isScalarAsTargetTypeName = codegen_emit_storage_values.isScalarAsTargetTypeName;
const inferSetCallType = codegen_emit_storage_values.inferSetCallType;
const callbackBindingsHaveSameShape = codegen_emit_storage_values.callbackBindingsHaveSameShape;
const callArgMatchesParam = codegen_emit_storage_values.callArgMatchesParam;
const inferPutCallType = codegen_emit_storage_values.inferPutCallType;
const callArgsMatchVariadicTail = codegen_emit_storage_values.callArgsMatchVariadicTail;
const callArgMatchesUnionParam = codegen_emit_storage_values.callArgMatchesUnionParam;
const unionTypeNameHasBranch = codegen_emit_storage_values.unionTypeNameHasBranch;
const inferFieldGetCallType = codegen_emit_storage_values.inferFieldGetCallType;
const funcVariadicElemType = codegen_emit_storage_values.funcVariadicElemType;
const inferFieldSetCallType = codegen_emit_storage_values.inferFieldSetCallType;
const findFieldMetaLocal = codegen_emit_storage_values.findFieldMetaLocal;
const structLiteralExprMatchesType = codegen_emit_storage_values.structLiteralExprMatchesType;
const inferGetCallType = codegen_emit_storage_values.inferGetCallType;
const lambdaExprShape = codegen_emit_storage_values.lambdaExprShape;
const lambdaParamCount = codegen_emit_storage_values.lambdaParamCount;
const callbackBindingHasSameConcreteArg = codegen_emit_storage_values.callbackBindingHasSameConcreteArg;
const valueEnumBranchValue = codegen_emit_storage_values.valueEnumBranchValue;
const inferTupleFieldPathGetType = codegen_emit_storage_values.inferTupleFieldPathGetType;
const appendManagedStructFieldMetaLocal = codegen_emit_storage_values.appendManagedStructFieldMetaLocal;
const fieldFromMeta = codegen_emit_storage_values.fieldFromMeta;
const findStructField = codegen_emit_storage_values.findStructField;
const unionLocalDefaultPayloadType = codegen_emit_storage_values.unionLocalDefaultPayloadType;
const unionLocalDefaultStructPayload = codegen_emit_storage_values.unionLocalDefaultStructPayload;
const findNarrowedUnionType = codegen_emit_storage_values.findNarrowedUnionType;
const isDotIdent = codegen_emit_storage_values.isDotIdent;
const isArrowAt = codegen_emit_storage_values.isArrowAt;
const lambdaBodyStart = codegen_emit_storage_values.lambdaBodyStart;
const lambdaParamTypeName = codegen_emit_storage_values.lambdaParamTypeName;
const lambdaExplicitReturnType = codegen_emit_storage_values.lambdaExplicitReturnType;
const appendTypedLocalWithDecl = codegen_emit_storage_values.appendTypedLocalWithDecl;
const appendTypedLocal = codegen_emit_storage_values.appendTypedLocal;
const inferLambdaExprReturnType = codegen_emit_storage_values.inferLambdaExprReturnType;
const cloneLocalSet = codegen_emit_storage_values.cloneLocalSet;
const callbackFunctionMatchesShape = codegen_emit_storage_values.callbackFunctionMatchesShape;
const callbackLambdaReturnMatchesShape = codegen_emit_storage_values.callbackLambdaReturnMatchesShape;
const findCallbackRefFunc = codegen_emit_storage_values.findCallbackRefFunc;
const lambdaExplicitTypesMatchShape = codegen_emit_storage_values.lambdaExplicitTypesMatchShape;
const typeBaseName = codegen_emit_storage_values.typeBaseName;
const valueEnumTypeMatchesImportAlias = codegen_emit_storage_values.valueEnumTypeMatchesImportAlias;
const findValueEnumBranchValue = codegen_emit_storage_values.findValueEnumBranchValue;
const valueEnumBranchValueInLine = codegen_emit_storage_values.valueEnumBranchValueInLine;
const valueEnumSourceMatchesImport = codegen_emit_storage_values.valueEnumSourceMatchesImport;
const managedPayloadElemTypeFromName = codegen_emit_storage_values.managedPayloadElemTypeFromName;
const absResultType = codegen_emit_storage_values.absResultType;
const inferFirstArgTypeOrDefaultS32 = codegen_emit_storage_values.inferFirstArgTypeOrDefaultS32;
const wasiDoResultType = codegen_emit_storage_values.wasiDoResultType;
const memoryLoadResultType = codegen_emit_storage_values.memoryLoadResultType;
const inferPathGetCallType = codegen_emit_storage_values.inferPathGetCallType;
const inferManagedStructExprFieldType = codegen_emit_storage_values.inferManagedStructExprFieldType;
const findConcreteStructFieldTypeNoAlloc = codegen_emit_storage_values.findConcreteStructFieldTypeNoAlloc;
const genericTypeArgAt = codegen_emit_storage_values.genericTypeArgAt;
const emit_managed_handle_call_expr_with_move_context = codegen_emit_storage_values.emit_managed_handle_call_expr_with_move_context;
const emit_storage_handle_binding_expr = codegen_emit_storage_values.emit_storage_handle_binding_expr;
const emit_tuple_call_binding = codegen_emit_storage_values.emit_tuple_call_binding;
pub fn emit_struct_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, decl: StructDecl, out: *std.ArrayList(u8)) !void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const source_name = tokens[start_idx].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, source_name);
    const target_name = if (struct_local) |local| local.name else resolved_local_name(locals.locals.items, source_name);
    const struct_ty = if (struct_local) |local|
        local.ty
    else if (try typed_struct_binding(allocator, tokens, start_idx, end_idx, ctx, &owned_types)) |binding|
        binding.ty
    else if (inferred_struct_binding(tokens, start_idx, end_idx, locals, ctx)) |binding|
        binding.ty
    else
        decl.name;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    if (findStructLayout(ctx.struct_layouts, struct_ty) != null and !is_struct_literal_rhs(tokens, eq_idx + 1, end_idx)) {
        if (try emit_managed_struct_set_binding(allocator, tokens, eq_idx + 1, end_idx, target_name, locals, ctx, decl, struct_ty, &owned_types, out)) {
            return;
        }
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
            struct_ty,
            out,
        );
        if (!emitted_move_call and !try codegen_callbacks.emit_expr(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, struct_ty, out)) return error.NoMatchingCall;
        if (!emitted_move_call and isDirectManagedLocalExpr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }
    if (findStructLayout(ctx.struct_layouts, struct_ty) == null) {
        if (try emit_wasi_record_struct_binding(allocator, tokens, start_idx, end_idx, locals, ctx, decl, out)) {
            return;
        }
        if (try emit_unmanaged_struct_call_binding(
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
        if (!is_struct_literal_rhs(tokens, eq_idx + 1, end_idx)) {
            if (!try codegen_callbacks.emit_expr(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, struct_ty, out)) return error.NoMatchingCall;
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
        try emit_managed_struct_fields(allocator, tokens, open_brace + 1, close_brace, target_name, locals, ctx, decl, struct_ty, layout, &owned_types, out);
        return;
    }

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = find_struct_literal_field(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        try emit_struct_field_value(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, false, out);
        try emit_struct_field_local_set(allocator, tokens, target_name, field_name, field_ty, locals, ctx, out);
    }
}

pub fn emit_unmanaged_struct_call_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, decl: StructDecl, struct_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
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
    if (!try codegen_callbacks.emit_user_func_call_with_move_context(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }

    var i = decl.fields.len;
    while (i > 0) {
        i -= 1;
        const field = decl.fields[i];
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        try emit_struct_field_local_set(allocator, tokens, tokens[start_idx].lexeme, publicDeclName(field.name), field_ty, locals, ctx, out);
    }
    return true;
}

pub fn emit_unmanaged_struct_error_union_return(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_struct: ?[]const u8, defer_ctx: ?*const DeferContext, out: *std.ArrayList(u8)) !bool {
    const error_name = unmanaged_struct_error_union_result(tokens, ctx, result_tys, result_struct) orelse return false;
    const struct_name = result_struct.?;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (start_idx + 1 >= end_idx) return error.NoMatchingCall;

    const expr_start = start_idx + 1;
    const expr_end = end_idx;
    const range = trimParens(tokens, expr_start, expr_end);

    if (try emit_unmanaged_struct_error_union_from_call(
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

    return emit_unmanaged_struct_error_union_from_ident(
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

fn result_types_match(result_tys: []const []const u8, func_results: []const []const u8) bool {
    if (func_results.len != result_tys.len) return false;
    for (result_tys, 0..) |result_ty, i| {
        if (!std.mem.eql(u8, result_ty, func_results[i])) return false;
    }
    return true;
}

/// Returns `null` when RHS is not a call (caller may try other shapes);
/// `true`/`false` when a call was handled or rejected.
fn emit_unmanaged_struct_error_union_from_call(
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
    if (!result_types_match(result_tys, func.results)) return false;

    const move_ctx = CallLastUseMoveContext{
        .body_start = body_start,
        .stmt_end = end_idx,
        .body_end = end_idx,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    };
    return try codegen_callbacks.emit_user_func_call_with_move_context(
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

fn emit_unmanaged_struct_error_union_from_ident(
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
            try emit_struct_fields_from_local(allocator, tokens, struct_local, decl, locals, ctx, false, out);
            try out.appendSlice(allocator, "    i32.const 0\n");
            return true;
        }
    }

    const is_error_branch = error_enum_branch_value(tokens, error_name, name) != null;
    const is_error_local = std.mem.eql(u8, findLocalType(locals.locals.items, name) orelse "", error_name);
    if (!is_error_branch and !is_error_local) return false;

    for (decl.fields) |field| {
        try emit_zero_value_for_type(allocator, ctx, out, field.ty);
    }
    if (!try codegen_callbacks.emit_expr(allocator, tokens, range.start, range.end, locals, ctx, error_name, out)) {
        return error.NoMatchingCall;
    }
    return true;
}

pub fn emit_user_func_arg(allocator: std.mem.Allocator, tokens: []const lexer.Token, arg_start: usize, arg_end: usize, param_ty: []const u8, copy_managed: bool, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parse_type_union_layout_from_name(allocator, tokens, param_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        return try codegen_callbacks.emit_union_value(allocator, tokens, arg_start, arg_end, locals, ctx, layout, copy_managed, null, out);
    }
    if (is_tuple_type_name(param_ty)) {
        if (try emit_tuple_expr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out)) {
            return true;
        }
    }
    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        if (findStructLocal(locals.struct_locals.items, tokens[range.start].lexeme)) |struct_local| {
            if (std.mem.eql(u8, struct_local.ty, param_ty) and findStructLayout(ctx.struct_layouts, param_ty) == null) {
                const decl = findStructDecl(ctx.structs, param_ty) orelse return false;
                try emit_struct_fields_from_local(allocator, tokens, struct_local, decl, locals, ctx, false, out);
                return true;
            }
        }
        if (try codegen_callbacks.emit_union_struct_payload_for_type(allocator, tokens, tokens[range.start].lexeme, param_ty, locals, ctx, false, out)) {
            return true;
        }
    }
    return try codegen_callbacks.emit_expr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out);
}

pub fn emit_struct_literal_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, expected_ty: []const u8, out: *std.ArrayList(u8)) CodegenError!bool {
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
        try emit_managed_struct_fields(allocator, tokens, open_brace + 1, close_brace, STRUCT_LITERAL_TMP_LOCAL, locals, ctx, decl, expected_ty, layout, &owned_types, out);
        try appendFmt(allocator, out, "    local.get ${s}\n", .{STRUCT_LITERAL_TMP_LOCAL});
        return true;
    }

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = find_struct_literal_field(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substituteStructFieldType(allocator, decl, expected_ty, field.ty, &owned_types);
        try emit_struct_field_value(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, false, out);
    }
    return true;
}

pub fn emit_struct_set_assignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
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
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return false;
        try appendFmt(allocator, out, "    ;; arc-managed-struct-set name={s} field={s} offset={d}\n", .{
            tokens[start_idx].lexeme,
            field_name,
            field_offset,
        });
        if (is_managed_struct_field(layout, field_name)) {
            try emit_managed_struct_field_set(
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
        try append_managed_struct_field_ptr(allocator, out, tokens[start_idx].lexeme, field_offset);
        if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try appendStoreForPayloadType(allocator, out, field_ty);
        return true;
    }

    if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}

pub fn resolved_local_name(locals: []const Local, name: []const u8) []const u8 {
    return findLocalName(locals, name) orelse name;
}

fn type_args_close_idx(tokens: []const lexer.Token, open_angle: usize, end_idx: usize) ?usize {
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

pub fn stmt_contains_struct_literal_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and tokEq(tokens[i + 1], "{")) return true;
        if (tokens[i].kind == .ident and tokEq(tokens[i + 1], "<")) {
            const close = type_args_close_idx(tokens, i + 1, end_idx) orelse continue;
            if (close + 1 < end_idx and tokEq(tokens[close + 1], "{")) return true;
        }
        if (tokEq(tokens[i], ".") and tokEq(tokens[i + 1], "{")) return true;
    }
    return false;
}

pub fn emit_unmanaged_struct_return_local(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_struct: ?[]const u8, out: *std.ArrayList(u8)) !bool {
    const struct_name = result_struct orelse return false;
    if (is_tuple_type_name(struct_name)) return false;
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

pub fn emit_managed_struct_set_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, decl: StructDecl, struct_ty: []const u8, owned_types: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) CodegenError!bool {
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
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return false;
        try append_managed_struct_field_ptr(allocator, out, target_name, field_offset);
        if (std.mem.eql(u8, field_name, target_field)) {
            if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            if (is_managed_struct_field(layout, field_name) and isDirectManagedLocalExpr(tokens, value_start, value_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendStoreForPayloadType(allocator, out, field_ty);
            continue;
        }

        try append_managed_struct_field_ptr(allocator, out, source_local.name, field_offset);
        try append_load_for_payload_type(allocator, out, field_ty);
        if (is_managed_struct_field(layout, field_name)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }
    return true;
}

pub fn emit_managed_struct_fields(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, local_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, decl: StructDecl, struct_ty: []const u8, layout: StructLayout, owned_types: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) !void {
    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = find_struct_literal_field(tokens, start_idx, end_idx, field_name);
        const expr_tokens = if (literal_field) |_| tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return error.NoMatchingCall;
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, owned_types);

        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try out.appendSlice(allocator, "    call $__arc_payload\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        if (!try codegen_callbacks.emit_expr(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        if (is_managed_struct_field(layout, field_name) and isDirectManagedLocalExpr(expr_tokens, expr_start, expr_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }
}

pub fn emit_struct_set_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected_ty: ?[]const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
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
            if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            continue;
        }
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            struct_local.name,
            field_name,
        });
    }
    return true;
}

pub fn unmanaged_struct_error_union_result(
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
