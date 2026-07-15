const std = @import("std");
const codegen_ir = @import("codegen_ir.zig");
const wat_component_metadata = @import("wat_component_metadata.zig");
const wat_function_body = @import("wat_function_body.zig");
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
const find_storage_local_origin = context.find_storage_local_origin;
const is_compiler_local_name = context.is_compiler_local_name;
const union_payload_local_name = context.union_payload_local_name;
const union_tag_local_name = context.union_tag_local_name;
const find_union_local_exact = context.find_union_local_exact;
const append_loop_source_storage_local = context.append_loop_source_storage_local;
const local_name_matches = context.local_name_matches;
const loop_source_local_name = context.loop_source_local_name;
const free_callback_bindings = model.free_callback_bindings;
const free_struct_decls = model.free_struct_decls;
const free_struct_decl = model.free_struct_decl;
const free_value_enum_decls = model.free_value_enum_decls;
const free_payload_enum_decls = model.free_payload_enum_decls;
const free_struct_layouts = model.free_struct_layouts;
const free_func_params = model.free_func_params;
const free_func_decls = model.free_func_decls;
const free_func_result_items = model.free_func_result_items;
const freeWasiHostImports = codegen_wasi_registry.free_wasi_host_imports;
const collectWasiHostImports = codegen_wasi_registry.collect_wasi_host_imports;
const collectWasiHostImportsFromModules = codegen_wasi_registry.collect_wasi_host_imports_from_modules;
const wasi_lowering = codegen_wasi_registry.wasi_lowering;
const append_wasi_import_symbol = codegen_wasi_registry.append_wasi_import_symbol;
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
const find_local_type = context.find_local_type;
const find_local_origin = context.find_local_origin;
const find_storage_local = context.find_storage_local;
const find_struct_local = context.find_struct_local;
const find_union_local = context.find_union_local;
const has_local = context.has_local;
const storage_type_name_for_elem = context.storage_type_name_for_elem;
const storage_type_name_for_elem_owned = context.storage_type_name_for_elem_owned;

const UnionLayout = codegen_union_layout.UnionLayout;
const UnionBranch = codegen_union_layout.UnionBranch;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const cloneUnionLayout = codegen_union_layout.clone_union_layout;
const unionLayoutsEqual = codegen_union_layout.union_layouts_equal;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const validateWasiHostImportBuildUses = codegen_wasi_registry.validate_wasi_host_import_build_uses;
const WASI_BINDING_ENTRY_SOURCE = codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE;

const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const findLineStart = codegen_tokens.find_line_start;
const is_line_start = codegen_tokens.is_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const publicDeclName = codegen_names.public_decl_name;
const append_fmt = codegen_names.append_fmt;
const Range = codegen_tokens.Range;
const align_up = codegen_tokens.align_up;
const compactTokenText = codegen_tokens.compact_token_text;
const string_token_body = codegen_tokens.string_token_body;
const decodeQuotedStringToken = codegen_tokens.decode_quoted_string_token;
const has_string = codegen_names.has_string;
const findTopLevelTypeSeparator = codegen_tokens.find_top_level_type_separator;
const find_top_level_type_separator_from = codegen_tokens.find_top_level_type_separator_from;

const CallLastUseMoveContext = context.CallLastUseMoveContext;
const codegen_host_imports = @import("codegen_host_imports.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_collect_declarations = @import("codegen_collect_declarations.zig");
const codegen_body = @import("codegen_body.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const tuple_element_type_at = codegen_storage_layout.tuple_element_type_at;
const tuple_scalar_leaf_storage_byte_width_ctx = codegen_storage_layout.tuple_scalar_leaf_storage_byte_width_ctx;
const find_storage_primitive_local = codegen_storage_layout.find_storage_primitive_local;
const is_storage_type_name = codegen_storage_layout.is_storage_type_name;
const tuple_arity = codegen_storage_layout.tuple_arity;
const is_tuple_type_name = codegen_storage_layout.is_tuple_type_name;
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_emit_storage_values = @import("codegen_emit_storage_values.zig");
const codegen_emit_storage_operations = @import("codegen_emit_storage_operations.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_emit_expression = @import("codegen_emit_expression.zig");
const codegen_emit_call = @import("codegen_emit_call.zig");
const codegen_generics = @import("codegen_generics.zig");
const collect_body_locals_with_mode = codegen_body.collect_body_locals_with_mode;
// Re-export expression and call emit entry points.
const emit_start_func = codegen_emit_expression.emit_start_func;
pub const emit_scalar_numeric_start_with_backend_ir = codegen_emit_expression.emit_scalar_numeric_start_with_backend_ir;
const emit_test_funcs = codegen_emit_expression.emit_test_funcs;
const emit_user_funcs = codegen_emit_expression.emit_user_funcs;

// Re-export generic instantiation (physical home: codegen_generics.zig).
pub const append_unmanaged_struct_result_abi = codegen_generics.append_unmanaged_struct_result_abi;
pub const bind_explicit_generic_call_type_args = codegen_generics.bind_explicit_generic_call_type_args;
pub const bind_generic_callback_arg = codegen_generics.bind_generic_callback_arg;
pub const bind_generic_callback_ident_arg = codegen_generics.bind_generic_callback_ident_arg;
pub const bind_generic_callback_lambda_arg = codegen_generics.bind_generic_callback_lambda_arg;
pub const bind_generic_expected_result = codegen_generics.bind_generic_expected_result;
pub const bind_generic_func_call = codegen_generics.bind_generic_func_call;
pub const bind_generic_type_from_concrete = codegen_generics.bind_generic_type_from_concrete;
pub const bind_generic_type_list_from_concrete = codegen_generics.bind_generic_type_list_from_concrete;
pub const bind_generic_variadic_tail = codegen_generics.bind_generic_variadic_tail;
pub const callback_bindings_for_call = codegen_generics.callback_bindings_for_call;
pub const callback_bindings_have_same_concrete_args = codegen_generics.callback_bindings_have_same_concrete_args;
pub const clone_func_params = codegen_generics.clone_func_params;
pub const clone_generic_type_bindings_owned = codegen_generics.clone_generic_type_bindings_owned;
pub const collect_concrete_callback_func_instance_for_call = codegen_generics.collect_concrete_callback_func_instance_for_call;
pub const collect_generic_func_instance_for_call = codegen_generics.collect_generic_func_instance_for_call;
pub const collect_generic_func_instances_for_call = codegen_generics.collect_generic_func_instances_for_call;
pub const collect_generic_func_instances_for_concrete_funcs = codegen_generics.collect_generic_func_instances_for_concrete_funcs;
pub const collect_generic_func_instances_for_start = codegen_generics.collect_generic_func_instances_for_start;
pub const collect_generic_func_instances_for_tests = codegen_generics.collect_generic_func_instances_for_tests;
pub const collect_generic_func_instances_in_call_args = codegen_generics.collect_generic_func_instances_in_call_args;
pub const collect_generic_func_instances_in_field_reflection_loop = codegen_generics.collect_generic_func_instances_in_field_reflection_loop;
pub const collect_generic_func_instances_in_guard_loop_control = codegen_generics.collect_generic_func_instances_in_guard_loop_control;
pub const collect_generic_func_instances_in_guard_return = codegen_generics.collect_generic_func_instances_in_guard_return;
pub const collect_generic_func_instances_in_range = codegen_generics.collect_generic_func_instances_in_range;
pub const collect_generic_func_instances_in_start_body = codegen_generics.collect_generic_func_instances_in_start_body;
pub const concrete_overload_covers_generic_params = codegen_generics.concrete_overload_covers_generic_params;
pub const direct_call_expected_result_type = codegen_generics.direct_call_expected_result_type;
pub const explicit_lambda_types_match = codegen_generics.explicit_lambda_types_match;
pub const find_generic_template_for_call = codegen_generics.find_generic_template_for_call;
pub const func_has_untyped_params = codegen_generics.func_has_untyped_params;
pub const func_params_have_same_concrete_call_shape = codegen_generics.func_params_have_same_concrete_call_shape;
pub const generic_bindings_cover_type_params = codegen_generics.generic_bindings_cover_type_params;
pub const generic_instance_name = codegen_generics.generic_instance_name;
pub const generic_overload_covers_generic_params = codegen_generics.generic_overload_covers_generic_params;
pub const generic_template_logical_result_type = codegen_generics.generic_template_logical_result_type;
pub const generic_template_matches_call_site = codegen_generics.generic_template_matches_call_site;
pub const generic_template_matches_concrete_params = codegen_generics.generic_template_matches_concrete_params;
pub const generic_template_specificity = codegen_generics.generic_template_specificity;
pub const infer_generic_call_union_result_layout = codegen_generics.infer_generic_call_union_result_layout;
pub const infer_untyped_generic_param_abi_type = codegen_generics.infer_untyped_generic_param_abi_type;
pub const instantiate_callback_shape = codegen_generics.instantiate_callback_shape;
pub const instantiate_func_type_shape = codegen_generics.instantiate_func_type_shape;
pub const instantiate_generic_func_result_items = codegen_generics.instantiate_generic_func_result_items;
pub const match_or_bind_generic_type = codegen_generics.match_or_bind_generic_type;
pub const parse_lambda_param_names = codegen_generics.parse_lambda_param_names;
pub const parse_lambda_param_types = codegen_generics.parse_lambda_param_types;
pub const prebind_generic_callback_arg = codegen_generics.prebind_generic_callback_arg;
pub const prebind_generic_callback_args = codegen_generics.prebind_generic_callback_args;
pub const prebind_generic_callback_func_ref = codegen_generics.prebind_generic_callback_func_ref;
pub const prebind_generic_callback_ident = codegen_generics.prebind_generic_callback_ident;
pub const prebind_generic_callback_lambda = codegen_generics.prebind_generic_callback_lambda;
pub const prebind_generic_type_if_param = codegen_generics.prebind_generic_type_if_param;
pub const resolve_callback_binding_arg = codegen_generics.resolve_callback_binding_arg;
pub const type_contains_type_param = codegen_generics.type_contains_type_param;
pub const typed_binding_expected_type = codegen_generics.typed_binding_expected_type;

pub fn collect_body_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) anyerror!void {
    install_gen_hooks();
    return codegen_body.collect_body_locals(allocator, tokens, start_idx, end_idx, ctx, out);
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
    install_gen_hooks();
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
    install_gen_hooks();
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
const codegen_ownership = @import("codegen_ownership.zig");
const find_top_level_guard_loop_control = codegen_ownership.find_top_level_guard_loop_control;

// re-export codegen_host_imports
const collect_env_host_imports = codegen_host_imports.collect_env_host_imports;
const collect_env_host_imports_from_modules = codegen_host_imports.collect_env_host_imports_from_modules;
const parse_env_host_import = codegen_host_imports.parse_env_host_import;
const find_host_import = codegen_host_imports.find_host_import;
const find_host_import_for_tokens = codegen_host_imports.find_host_import_for_tokens;
const is_env_host_import_start = codegen_host_imports.is_env_host_import_start;
const free_host_imports = codegen_host_imports.free_host_imports;
const host_call_args_match = codegen_host_imports.host_call_args_match;
const host_param_is_ptr_len = codegen_host_imports.host_param_is_ptr_len;
const host_arg_could_be_storage_ptr_len_syntax = codegen_host_imports.host_arg_could_be_storage_ptr_len_syntax;
// Re-export token and name helpers used by lower-level tests.
const module_tokens_equal = codegen_tokens.module_tokens_equal;
pub const find_start_func = codegen_tokens.find_start_func;
pub const find_token = codegen_tokens.find_token;
const findTopLevelBlockOpen = codegen_tokens.find_top_level_block_open;
const find_stmt_end = codegen_tokens.find_stmt_end;
const findTypeArgEnd = codegen_tokens.find_type_arg_end;
const stringLiteralArgLexeme = codegen_tokens.string_literal_arg_lexeme;
const isStringLiteralArg = codegen_tokens.is_string_literal_arg;
const isTypedBindingRhsCall = codegen_tokens.is_typed_binding_rhs_call;
const isBareHostCallStatement = codegen_tokens.is_bare_host_call_statement;
const moduleScopedSymbolName = codegen_names.module_scoped_symbol_name;
const appendMangledTypeName = codegen_names.append_mangled_type_name;
const isPublicTypeName = codegen_names.is_public_type_name;
const is_error_type_name = codegen_names.is_error_type_name;
const is_base_int_type_name = codegen_names.is_base_int_type_name;
const isNumericCoreFuncName = codegen_names.is_numeric_core_func_name;
const isBitwiseCoreFuncName = codegen_names.is_bitwise_core_func_name;
const isCountBitsCoreFuncName = codegen_names.is_count_bits_core_func_name;
const isNumericUnarySelectCoreFuncName = codegen_names.is_numeric_unary_select_core_func_name;
const isNumericBinarySelectCoreFuncName = codegen_names.is_numeric_binary_select_core_func_name;
const isFloatUnaryCoreFuncName = codegen_names.is_float_unary_core_func_name;
const isFloatBinaryCoreFuncName = codegen_names.is_float_binary_core_func_name;
const isBoolSpecialFuncName = codegen_names.is_bool_special_func_name;
const isComparisonCoreFuncName = codegen_names.is_comparison_core_func_name;
const is_memory_load_name = codegen_names.is_memory_load_name;
const isCoreWasmCallName = codegen_names.is_core_wasm_call_name;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;
const is_core_integer_scalar = codegen_names.is_core_integer_scalar;
const is_core_float_scalar = codegen_names.is_core_float_scalar;
const isUserFuncDeclStart = codegen_tokens.is_user_func_decl_start;
const tokenTextEqualsCompact = codegen_tokens.token_text_equals_compact;
// re-export codegen_imports
const validate_host_import_build_uses = codegen_imports.validate_host_import_build_uses;
const validate_reachable_wasi_host_import_build_uses = codegen_imports.validate_reachable_wasi_host_import_build_uses;
const validate_reachable_wasi_host_import_build_uses_from_tests = codegen_imports.validate_reachable_wasi_host_import_build_uses_from_tests;
const validate_reachable_wasi_host_import_stack = codegen_imports.validate_reachable_wasi_host_import_stack;
const find_root_module_index = codegen_imports.find_root_module_index;
const wasi_source_for_tokens = codegen_imports.wasi_source_for_tokens;
const find_wasi_host_import_for_tokens = codegen_imports.find_wasi_host_import_for_tokens;
const has_reach_visit = codegen_imports.has_reach_visit;
const push_reach_visit = codegen_imports.push_reach_visit;
const collect_start_body_calls = codegen_imports.collect_start_body_calls;
const collect_all_function_body_calls = codegen_imports.collect_all_function_body_calls;
const collect_test_body_calls = codegen_imports.collect_test_body_calls;
const collect_function_body_calls = codegen_imports.collect_function_body_calls;
const collect_call_names_in_range = codegen_imports.collect_call_names_in_range;
const is_loop_source_special_call_name = codegen_imports.is_loop_source_special_call_name;
const find_codegen_import_by_alias = codegen_imports.find_codegen_import_by_alias;
const parse_codegen_import = codegen_imports.parse_codegen_import;
const imported_scalar_const = codegen_imports.imported_scalar_const;
const find_imported_module_index_no_alloc = codegen_imports.find_imported_module_index_no_alloc;
const module_matches_import_path = codegen_imports.module_matches_import_path;
const path_has_base_and_file = codegen_imports.path_has_base_and_file;
const local_scalar_const = codegen_imports.local_scalar_const;
const find_imported_module_index = codegen_imports.find_imported_module_index;
const find_module_by_path = codegen_imports.find_module_by_path;
const is_value_enum_decl_start = codegen_imports.is_value_enum_decl_start;
const is_payload_enum_decl_start = codegen_imports.is_payload_enum_decl_start;
const find_value_enum_decl = codegen_imports.find_value_enum_decl;
const find_payload_enum_decl = codegen_imports.find_payload_enum_decl;
const find_value_enum_decl_line_by_name = codegen_imports.find_value_enum_decl_line_by_name;
const find_value_enum_decl_line_by_branch = codegen_imports.find_value_enum_decl_line_by_branch;
const value_enum_line_has_branch = codegen_imports.value_enum_line_has_branch;
const collect_string_data_for_host_calls = codegen_imports.collect_string_data_for_host_calls;
const collect_string_data_for_wasi_host_calls = codegen_imports.collect_string_data_for_wasi_host_calls;
const collect_string_data_for_storage_literals = codegen_imports.collect_string_data_for_storage_literals;
const collect_string_data_for_struct_field_names = codegen_imports.collect_string_data_for_struct_field_names;
const has_borrowed_name = codegen_imports.has_borrowed_name;
const imported_alias_context_for_tokens = codegen_imports.imported_alias_context_for_tokens;
pub const call_head_at = codegen_imports.call_head_at;
const expr_call_head = codegen_imports.expr_call_head;
const call_head_has_type_args = codegen_imports.call_head_has_type_args;
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
const parse_codegen_type_expr = codegen_collect_util.parse_codegen_type_expr;
const parse_func_param_type_expr = codegen_collect_functions.parse_func_param_type_expr;
const is_top_level_comma_any = codegen_collect_functions.is_top_level_comma_any;
const collect_func_decls = codegen_collect_functions.collect_func_decls;
const collect_direct_imported_func_decls = codegen_collect_functions.collect_direct_imported_func_decls;
const collect_direct_imported_func_decls_from_tests = codegen_collect_functions.collect_direct_imported_func_decls_from_tests;
const bind_generic_type = codegen_collect_util.bind_generic_type;
pub const find_generic_binding = codegen_collect_util.find_generic_binding;
const substitute_generic_type_owned = codegen_collect_util.substitute_generic_type_owned;
const is_type_ident_start = codegen_collect_util.is_type_ident_start;
const is_type_ident_part = codegen_collect_util.is_type_ident_part;
const generic_type_args_range = codegen_collect_util.generic_type_args_range;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const has_type_param_name = codegen_collect_util.has_type_param_name;
const find_func_decl = codegen_collect_functions.find_func_decl;
pub const func_param_abi_type = codegen_collect_util.func_param_abi_type;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const append_tuple_leaf_types = codegen_collect_util.append_tuple_leaf_types;
// re-export codegen_emit_wasi
const codegen_types_compatible = codegen_storage_layout.codegen_types_compatible;
pub fn emit_wasi_resource_drop_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_resource_drop_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_list_u8_result_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_list_u8_result_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_unit_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_unit_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_descriptor_path_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_descriptor_path_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_output_write_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_output_write_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_descriptor_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_descriptor_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_descriptor_handle_arg(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_descriptor_handle_arg(allocator, tokens, start_idx, end_idx, locals, ctx, out, emit_expr);
}

pub fn emit_wasi_result_link_at_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_link_at_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_filesize_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_filesize_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_u64_stream_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_u64_stream_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_read_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_read_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

pub fn emit_wasi_result_list_u8_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, import: WasiHostImport, out: *std.ArrayList(u8)) CodegenError!bool {
    return codegen_emit_wasi.emit_wasi_result_list_u8_call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
}

fn install_gen_hooks() void {
    codegen_callbacks.install(codegen_emit_expression.emit_expr, codegen_emit_expression.emit_expr_with_move_context, codegen_emit_call.emit_user_func_call_with_move_context);
    codegen_callbacks.install_body(codegen_emit_control.emit_body);
    codegen_callbacks.install_union_value(codegen_emit_union.emit_union_value);
    codegen_callbacks.install_collect_body_locals(codegen_body.collect_body_locals);
    codegen_callbacks.install_collect_body_locals_with_mode(codegen_body.collect_body_locals_with_mode);
    codegen_callbacks.install_emit_multi_result_assignment(codegen_emit_call.emit_multi_result_assignment);
    codegen_callbacks.install_emit_bare_user_func_call(codegen_emit_call.emit_bare_user_func_call);
    codegen_callbacks.install_emit_bare_user_func_call_move(codegen_emit_call.emit_bare_user_func_call_with_move_context);
    codegen_callbacks.install_emit_user_func_call_union_binding_move(codegen_emit_call.emit_user_func_call_with_union_binding_move);
    codegen_callbacks.install_emit_union_struct_payload_for_type(codegen_emit_union.emit_union_struct_payload_for_type);
    codegen_callbacks.install_infer_generic_call_union_result(infer_generic_call_union_result_layout);
}

pub fn emit_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
    return emit_wat_with_options(allocator, program, tokens, module_graph, .{});
}

pub fn emit_wat_with_options(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph, options: EmitOptions) ![]u8 {
    install_gen_hooks();

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        free_host_imports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try collect_env_host_imports(allocator, tokens, &host_imports);
    if (module_graph) |graph| {
        try collect_env_host_imports_from_modules(allocator, graph.modules, tokens, &host_imports);
    }
    try validate_host_import_build_uses(tokens, host_imports.items);

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
        try validate_reachable_wasi_host_import_build_uses(allocator, tokens, graph);
    }

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    try collect_string_data_for_host_calls(allocator, tokens, host_imports.items, &string_data);
    try collect_string_data_for_wasi_host_calls(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, wasi_imports.items, &string_data);
    try collect_string_data_for_storage_literals(allocator, tokens, &string_data);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            const source = if (module_tokens_equal(module.tokens, tokens))
                WASI_BINDING_ENTRY_SOURCE
            else
                module.path;
            try collect_string_data_for_host_calls(allocator, module.tokens, host_imports.items, &string_data);
            try collect_string_data_for_wasi_host_calls(allocator, module.tokens, source, wasi_imports.items, &string_data);
            try collect_string_data_for_storage_literals(allocator, module.tokens, &string_data);
        }
    }

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        free_struct_decls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try collect_struct_decls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collect_imported_struct_decls(allocator, tokens, graph, &structs);
    }
    try collect_string_data_for_struct_field_names(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        free_value_enum_decls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collect_value_enum_decls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collect_imported_value_enum_decls(allocator, tokens, graph, &value_enums);
    }

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        free_payload_enum_decls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try collect_payload_enum_decls(allocator, tokens, &payload_enums);
    if (module_graph) |graph| {
        try collect_imported_payload_enum_decls(allocator, tokens, graph, &payload_enums);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        free_struct_layouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collect_struct_layouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (find_root_module_index(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collect_func_decls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collect_direct_imported_func_decls(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
    }
    try collect_generic_func_instances_for_start(
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
    try mangle_overloaded_function_names(allocator, &functions);

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
    try append_fmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try append_fmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try append_fmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try wat_component_metadata.emit_wasi_bindings(allocator, &out, wasi_imports.items);
    try wat_component_metadata.emit_wasi_core_imports(allocator, &out, wasi_imports.items);
    try wat_component_metadata.emit_host_imports(allocator, &out, host_imports.items);
    try runtime_prelude_wat.emit_string_data_memory(allocator, &out, string_data.items.items, .{ .component_core = options.component_core });
    try runtime_prelude_wat.emit_arc_runtime_prelude(allocator, &out, string_data.items.items, struct_layouts.items);
    try emit_user_funcs(allocator, ctx, &out);
    try emit_start_func(allocator, tokens, ctx, &out);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

pub fn emit_test_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
    install_gen_hooks();

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    const test_decls = try test_runner.collect_top_level_tests(allocator, tokens);
    defer allocator.free(test_decls);
    if (test_decls.len == 0) return error.NoTestDecl;

    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        free_host_imports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try collect_env_host_imports(allocator, tokens, &host_imports);
    if (module_graph) |graph| {
        try collect_env_host_imports_from_modules(allocator, graph.modules, tokens, &host_imports);
    }
    try validate_host_import_build_uses(tokens, host_imports.items);

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
        try validate_reachable_wasi_host_import_build_uses_from_tests(allocator, tokens, graph);
    }

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    try collect_string_data_for_host_calls(allocator, tokens, host_imports.items, &string_data);
    try collect_string_data_for_wasi_host_calls(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, wasi_imports.items, &string_data);
    try collect_string_data_for_storage_literals(allocator, tokens, &string_data);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            const source = if (module_tokens_equal(module.tokens, tokens))
                WASI_BINDING_ENTRY_SOURCE
            else
                module.path;
            try collect_string_data_for_host_calls(allocator, module.tokens, host_imports.items, &string_data);
            try collect_string_data_for_wasi_host_calls(allocator, module.tokens, source, wasi_imports.items, &string_data);
            try collect_string_data_for_storage_literals(allocator, module.tokens, &string_data);
        }
    }

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        free_struct_decls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try collect_struct_decls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collect_imported_struct_decls(allocator, tokens, graph, &structs);
    }
    try collect_string_data_for_struct_field_names(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        free_value_enum_decls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collect_value_enum_decls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collect_imported_value_enum_decls(allocator, tokens, graph, &value_enums);
    }

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        free_payload_enum_decls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try collect_payload_enum_decls(allocator, tokens, &payload_enums);
    if (module_graph) |graph| {
        try collect_imported_payload_enum_decls(allocator, tokens, graph, &payload_enums);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        free_struct_layouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collect_struct_layouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (find_root_module_index(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collect_func_decls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collect_direct_imported_func_decls_from_tests(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
    }
    try collect_generic_func_instances_for_tests(
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
    try mangle_overloaded_function_names(allocator, &functions);

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
    try append_fmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try append_fmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try append_fmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try append_fmt(allocator, &out, "  ;; compiled_test_count={d}\n", .{test_decls.len});
    try wat_component_metadata.emit_wasi_bindings(allocator, &out, wasi_imports.items);
    try wat_component_metadata.emit_wasi_core_imports(allocator, &out, wasi_imports.items);
    try wat_component_metadata.emit_host_imports(allocator, &out, host_imports.items);
    try runtime_prelude_wat.emit_string_data_memory(allocator, &out, string_data.items.items, .{});
    try runtime_prelude_wat.emit_arc_runtime_prelude(allocator, &out, string_data.items.items, struct_layouts.items);
    try emit_user_funcs(allocator, ctx, &out);
    try emit_test_funcs(allocator, tokens, test_decls, ctx, &out);
    try wat_function_body.emit_test_start_func(allocator, &out, test_decls.len);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

pub fn direct_managed_last_use_move_source_origin(
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

pub fn direct_managed_call_last_use_move_source_origin(
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

pub fn direct_managed_union_binding_call_move_source_origin(
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

pub fn mangle_overloaded_function_names(allocator: std.mem.Allocator, functions: *std.ArrayList(FuncDecl)) !void {
    for (functions.items, 0..) |func, idx| {
        if (func.is_generic_template) continue;
        if (!function_source_name_has_multiple_concrete_decls(functions.items, func.tokens, func.source_name)) continue;

        const next_name = try function_signature_symbol_name(allocator, func);
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

pub fn function_source_name_has_multiple_concrete_decls(functions: []const FuncDecl, tokens: []const lexer.Token, source_name: []const u8) bool {
    var count: usize = 0;
    for (functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, tokens)) continue;
        if (!same_callable_source_name(func.source_name, source_name)) continue;
        count += 1;
        if (count > 1) return true;
    }
    return false;
}

pub fn function_signature_symbol_name(allocator: std.mem.Allocator, func: FuncDecl) ![]u8 {
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

pub fn is_codegen_import_alias_reachable(allocator: std.mem.Allocator, graph: *const imports.ModuleGraph, root_idx: usize, alias: []const u8) !bool {
    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collect_start_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (visit.module_idx == root_idx and std.mem.eql(u8, visit.name, alias)) return true;
        if (has_reach_visit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        if (find_codegen_import_by_alias(module.tokens, visit.name)) |import_ref| {
            if (find_imported_module_index(allocator, graph, visit.module_idx, import_ref)) |child_idx| {
                try push_reach_visit(allocator, &stack, .{
                    .module_idx = child_idx,
                    .name = import_ref.target,
                });
            }
            continue;
        }

        try collect_function_body_calls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
    return false;
}

pub fn is_typed_scalar_binding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) bool {
    return typed_scalar_binding_type(tokens, start_idx, end_idx, ctx) != null;
}

pub fn is_storage_u8_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const parsed = parse_storage_type(tokens, start_idx, end_idx) orelse return false;
    return std.mem.eql(u8, parsed.elem_ty, "u8");
}

pub fn is_pack_terminal_leaf_type(ty: []const u8, structs: []const StructDecl) bool {
    if (type_util.is_tuple_packable_leaf_type(ty)) return true;
    return is_pack_managed_handle_leaf(ty, structs);
}

/// Append terminal pack leaf types in order.
/// Pure-scalar struct fields expand nested; managed-struct slots stay one handle leaf (type name).
/// Append terminal pack leaf types in order.
/// Pure-scalar struct fields expand nested; managed-struct slots stay one handle leaf (type name).
pub fn append_store_payload_or_tuple_from_stack(allocator: std.mem.Allocator, out: *std.ArrayList(u8), elem_ty: []const u8, base_local: []const u8, indent: []const u8) CodegenError!void {
    try payload_wat.append_store_payload_or_tuple_from_stack(allocator, out, elem_ty, base_local, indent);
}

pub fn append_load_payload_or_tuple_to_stack(allocator: std.mem.Allocator, out: *std.ArrayList(u8), elem_ty: []const u8, base_local: []const u8, indent: []const u8) CodegenError!void {
    try payload_wat.append_load_payload_or_tuple_to_stack(allocator, out, elem_ty, base_local, indent);
}
