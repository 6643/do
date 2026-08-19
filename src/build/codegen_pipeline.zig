const std = @import("std");
const codegen_ir = @import("codegen_ir.zig");
const wat_component_metadata = @import("wat_component_metadata.zig");
const wat_function_body = @import("wat_function_body.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const parser = @import("parser.zig");
const sema_tokens = @import("sema_tokens.zig");
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
const free_wasi_host_imports = codegen_wasi_registry.free_wasi_host_imports;
const collect_wasi_host_imports = codegen_wasi_registry.collect_wasi_host_imports;
const collect_wasi_host_imports_from_modules = codegen_wasi_registry.collect_wasi_host_imports_from_modules;
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
const free_union_layout = codegen_union_layout.free_union_layout;
const clone_union_layout = codegen_union_layout.clone_union_layout;
const union_layouts_equal = codegen_union_layout.union_layouts_equal;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const validate_wasi_host_import_build_uses = codegen_wasi_registry.validate_wasi_host_import_build_uses;
const WASI_BINDING_ENTRY_SOURCE = codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE;

const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const find_line_start = codegen_tokens.find_line_start;
const is_line_start = codegen_tokens.is_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const public_decl_name = codegen_names.public_decl_name;
const append_fmt = codegen_names.append_fmt;
const Range = codegen_tokens.Range;
const align_up = codegen_tokens.align_up;
const compact_token_text = codegen_tokens.compact_token_text;
const string_token_body = codegen_tokens.string_token_body;
const decode_quoted_string_token = codegen_tokens.decode_quoted_string_token;
const has_string = codegen_names.has_string;
const find_top_level_type_separator = codegen_tokens.find_top_level_type_separator;
const find_top_level_type_separator_from = codegen_tokens.find_top_level_type_separator_from;
const is_declared_type_name = sema_tokens.is_declared_type_name;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;

const CallLastUseMoveContext = context.CallLastUseMoveContext;
const codegen_host_imports = @import("codegen_host_imports.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_collect_declarations = @import("codegen_collect_declarations.zig");
const codegen_body = @import("codegen_body.zig");
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
const host_export_manifest = @import("host_export_manifest.zig");
const codegen_p3_wait_for = @import("codegen_p3_wait_for.zig");
const codegen_component_cabi_realloc = @import("codegen_component_cabi_realloc.zig");
const codegen_async_model = @import("codegen_async_model.zig");
const codegen_component_resource_probe = @import("codegen_component_resource_probe.zig");
const codegen_component_wasi_filesystem_preopen = @import("codegen_component_wasi_filesystem_preopen.zig");
const codegen_component_wasi_sockets = @import("codegen_component_wasi_sockets.zig");
const codegen_component_resource_async = @import("codegen_component_resource_async.zig");
const codegen_component_async = @import("codegen_component_async.zig");
const codegen_component_async_call = @import("codegen_component_async_call.zig");
const codegen_component_async_host_arg_plan = @import("codegen_component_async_host_arg_plan.zig");
const codegen_component_async_host_arg = @import("codegen_component_async_host_arg.zig");
const codegen_component_future_owned = @import("codegen_component_future_owned.zig");
const codegen_component_future_owned_plan = @import("codegen_component_future_owned_plan.zig");
const codegen_gc_core = @import("codegen_gc_core.zig");
const codegen_gc_sync = @import("codegen_gc_sync.zig");
pub const emit_gc_wat_for_supported_program = codegen_gc_sync.emit_gc_wat_for_supported_program;
const codegen_emit_generic_async = @import("codegen_emit_generic_async.zig");
const codegen_task_bridge = @import("codegen_task_bridge.zig");
pub const emit_p3_wait_for_wit = codegen_p3_wait_for.emit_component_wit_for_tokens;
pub const emit_p3_async_call_component_wit = codegen_component_async_call.emit_component_wit;
pub const emit_p3_owned_future_component_wit = codegen_component_future_owned.emit_component_wit;
const collect_body_locals_with_mode = codegen_body.collect_body_locals_with_mode;
// Re-export expression and call emit entry points.
const emit_start_func = codegen_emit_expression.emit_start_func;
const emit_scalar_numeric_start_with_backend_ir = codegen_emit_expression.emit_scalar_numeric_start_with_backend_ir;
const emit_test_funcs = codegen_emit_expression.emit_test_funcs;
const emit_user_funcs = codegen_emit_expression.emit_user_funcs;
const emit_host_exports = codegen_emit_expression.emit_host_exports;

// Generic helpers stay private to the pipeline orchestration.
const append_unmanaged_struct_result_abi = codegen_generics.append_unmanaged_struct_result_abi;
const bind_explicit_generic_call_type_args = codegen_generics.bind_explicit_generic_call_type_args;
const bind_generic_callback_arg = codegen_generics.bind_generic_callback_arg;
const bind_generic_callback_ident_arg = codegen_generics.bind_generic_callback_ident_arg;
const bind_generic_callback_lambda_arg = codegen_generics.bind_generic_callback_lambda_arg;
const bind_generic_expected_result = codegen_generics.bind_generic_expected_result;
const bind_generic_func_call = codegen_generics.bind_generic_func_call;
const bind_generic_type_from_concrete = codegen_generics.bind_generic_type_from_concrete;
const bind_generic_type_list_from_concrete = codegen_generics.bind_generic_type_list_from_concrete;
const bind_generic_variadic_tail = codegen_generics.bind_generic_variadic_tail;
const callback_bindings_for_call = codegen_generics.callback_bindings_for_call;
const callback_bindings_have_same_concrete_args = codegen_generics.callback_bindings_have_same_concrete_args;
const clone_func_params = codegen_generics.clone_func_params;
const clone_generic_type_bindings_owned = codegen_generics.clone_generic_type_bindings_owned;
const collect_concrete_callback_func_instance_for_call = codegen_generics.collect_concrete_callback_func_instance_for_call;
const collect_generic_func_instance_for_call = codegen_generics.collect_generic_func_instance_for_call;
const collect_generic_func_instances_for_call = codegen_generics.collect_generic_func_instances_for_call;
const collect_generic_func_instances_for_concrete_funcs = codegen_generics.collect_generic_func_instances_for_concrete_funcs;
const collect_generic_func_instances_for_start = codegen_generics.collect_generic_func_instances_for_start;
const collect_generic_func_instances_for_tests = codegen_generics.collect_generic_func_instances_for_tests;
const collect_generic_func_instances_in_call_args = codegen_generics.collect_generic_func_instances_in_call_args;
const collect_generic_func_instances_in_field_reflection_loop = codegen_generics.collect_generic_func_instances_in_field_reflection_loop;
const collect_generic_func_instances_in_guard_loop_control = codegen_generics.collect_generic_func_instances_in_guard_loop_control;
const collect_generic_func_instances_in_guard_return = codegen_generics.collect_generic_func_instances_in_guard_return;
const collect_generic_func_instances_in_range = codegen_generics.collect_generic_func_instances_in_range;
const collect_generic_func_instances_in_start_body = codegen_generics.collect_generic_func_instances_in_start_body;
const concrete_overload_covers_generic_params = codegen_generics.concrete_overload_covers_generic_params;
const direct_call_expected_result_type = codegen_generics.direct_call_expected_result_type;
const explicit_lambda_types_match = codegen_generics.explicit_lambda_types_match;
const find_generic_template_for_call = codegen_generics.find_generic_template_for_call;
const func_has_untyped_params = codegen_generics.func_has_untyped_params;
const func_params_have_same_concrete_call_shape = codegen_generics.func_params_have_same_concrete_call_shape;
const generic_bindings_cover_type_params = codegen_generics.generic_bindings_cover_type_params;
const generic_instance_name = codegen_generics.generic_instance_name;
const generic_overload_covers_generic_params = codegen_generics.generic_overload_covers_generic_params;
const generic_template_logical_result_type = codegen_generics.generic_template_logical_result_type;
const generic_template_matches_call_site = codegen_generics.generic_template_matches_call_site;
const generic_template_matches_concrete_params = codegen_generics.generic_template_matches_concrete_params;
const generic_template_specificity = codegen_generics.generic_template_specificity;
const infer_generic_call_union_result_layout = codegen_generics.infer_generic_call_union_result_layout;
const infer_untyped_generic_param_abi_type = codegen_generics.infer_untyped_generic_param_abi_type;
const instantiate_callback_shape = codegen_generics.instantiate_callback_shape;
const instantiate_func_type_shape = codegen_generics.instantiate_func_type_shape;
const instantiate_generic_func_result_items = codegen_generics.instantiate_generic_func_result_items;
const match_or_bind_generic_type = codegen_generics.match_or_bind_generic_type;
const parse_lambda_param_names = codegen_generics.parse_lambda_param_names;
const parse_lambda_param_types = codegen_generics.parse_lambda_param_types;
const prebind_generic_callback_arg = codegen_generics.prebind_generic_callback_arg;
const prebind_generic_callback_args = codegen_generics.prebind_generic_callback_args;
const prebind_generic_callback_func_ref = codegen_generics.prebind_generic_callback_func_ref;
const prebind_generic_callback_ident = codegen_generics.prebind_generic_callback_ident;
const prebind_generic_callback_lambda = codegen_generics.prebind_generic_callback_lambda;
const prebind_generic_type_if_param = codegen_generics.prebind_generic_type_if_param;
const resolve_callback_binding_arg = codegen_generics.resolve_callback_binding_arg;
const type_contains_type_param = codegen_generics.type_contains_type_param;
const typed_binding_expected_type = codegen_generics.typed_binding_expected_type;

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
const field_get_last_use_move_source = codegen_emit_struct_fields.field_get_last_use_move_source;
const apply_guard_loop_control_narrowing = codegen_emit_struct_fields.apply_guard_loop_control_narrowing;
const apply_collect_guard_return_narrowing = codegen_emit_struct_fields.apply_collect_guard_return_narrowing;
// re-export codegen_emit_storage_values
const parse_storage_type = codegen_storage_layout.parse_storage_type;
const substitute_struct_field_type = codegen_storage_layout.substitute_struct_field_type;
const find_func_decl_for_call_head = codegen_storage_layout.find_func_decl_for_call_head;
const infer_expr_type = codegen_storage_layout.infer_expr_type;
const direct_managed_last_use_move_source = codegen_emit_storage_values.direct_managed_last_use_move_source;
const find_callback_binding = codegen_storage_layout.find_callback_binding;
const callback_bindings_have_same_shape = codegen_storage_layout.callback_bindings_have_same_shape;
const call_arg_matches_param = codegen_storage_layout.call_arg_matches_param;
const call_args_match_variadic_tail = codegen_storage_layout.call_args_match_variadic_tail;
const func_variadic_elem_type = codegen_storage_layout.func_variadic_elem_type;
const lambda_expr_shape = codegen_storage_layout.lambda_expr_shape;
const callback_binding_has_same_concrete_arg = codegen_storage_layout.callback_binding_has_same_concrete_arg;
const lambda_param_type_name = codegen_storage_layout.lambda_param_type_name;
const lambda_explicit_return_type = codegen_storage_layout.lambda_explicit_return_type;
const infer_lambda_expr_return_type = codegen_storage_layout.infer_lambda_expr_return_type;
const clone_local_set = codegen_storage_layout.clone_local_set;
const find_callback_ref_func = codegen_storage_layout.find_callback_ref_func;
const codegen_control_flow = @import("codegen_control_flow.zig");
const find_top_level_guard_loop_control = codegen_control_flow.find_top_level_guard_loop_control;

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
const find_start_func = codegen_tokens.find_start_func;
const find_token = codegen_tokens.find_token;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const find_stmt_end = codegen_tokens.find_stmt_end;
const find_type_arg_end = codegen_tokens.find_type_arg_end;
const string_literal_arg_lexeme = codegen_tokens.string_literal_arg_lexeme;
const is_string_literal_arg = codegen_tokens.is_string_literal_arg;
const is_typed_binding_rhs_call = codegen_tokens.is_typed_binding_rhs_call;
const is_bare_host_call_statement = codegen_tokens.is_bare_host_call_statement;
const module_scoped_symbol_name = codegen_names.module_scoped_symbol_name;
const append_mangled_type_name = codegen_names.append_mangled_type_name;
const is_public_type_name = codegen_names.is_public_type_name;
const is_error_type_name = codegen_names.is_error_type_name;
const is_base_int_type_name = codegen_names.is_base_int_type_name;
const is_numeric_core_func_name = codegen_names.is_numeric_core_func_name;
const is_bitwise_core_func_name = codegen_names.is_bitwise_core_func_name;
const is_count_bits_core_func_name = codegen_names.is_count_bits_core_func_name;
const is_numeric_unary_select_core_func_name = codegen_names.is_numeric_unary_select_core_func_name;
const is_numeric_binary_select_core_func_name = codegen_names.is_numeric_binary_select_core_func_name;
const is_float_unary_core_func_name = codegen_names.is_float_unary_core_func_name;
const is_float_binary_core_func_name = codegen_names.is_float_binary_core_func_name;
const is_bool_special_func_name = codegen_names.is_bool_special_func_name;
const is_comparison_core_func_name = codegen_names.is_comparison_core_func_name;
const is_memory_load_name = codegen_names.is_memory_load_name;
const is_core_wasm_call_name = codegen_names.is_core_wasm_call_name;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;
const is_core_integer_scalar = codegen_names.is_core_integer_scalar;
const is_core_float_scalar = codegen_names.is_core_float_scalar;
const is_user_func_decl_start = codegen_tokens.is_user_func_decl_start;
const token_text_equals_compact = codegen_tokens.token_text_equals_compact;
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
const call_head_at = codegen_imports.call_head_at;
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
const find_generic_binding = codegen_collect_util.find_generic_binding;
const substitute_generic_type_owned = codegen_collect_util.substitute_generic_type_owned;
const is_type_ident_start = codegen_collect_util.is_type_ident_start;
const is_type_ident_part = codegen_collect_util.is_type_ident_part;
const generic_type_args_range = codegen_collect_util.generic_type_args_range;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const has_type_param_name = codegen_collect_util.has_type_param_name;
const find_func_decl = codegen_collect_functions.find_func_decl;
const func_param_abi_type = codegen_collect_util.func_param_abi_type;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const append_tuple_leaf_types = codegen_collect_util.append_tuple_leaf_types;
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

fn program_has_async_func(program: parser.Program) bool {
    for (program.func_sigs) |sig| {
        if (sig.is_async or sig.contains_await or sig.resumable) return true;
    }
    return false;
}

pub fn program_requires_async_lowering(program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) bool {
    if (program_has_async_func(program)) return true;
    if (tokens_require_async_lowering(tokens)) return true;
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            if (tokens_require_async_lowering(module.tokens)) return true;
        }
    }
    return false;
}

fn tokens_require_async_lowering(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, "async")) return true;
        if (tok_eq(token, "await_all") or tok_eq(token, "await_any")) return true;
        if (!tok_eq(token, "@") or idx + 1 >= tokens.len) continue;
        if (tok_eq(tokens[idx + 1], "async") or tok_eq(tokens[idx + 1], "await") or
            tok_eq(tokens[idx + 1], "cancel")) return true;
    }
    return false;
}

fn tokens_have_gc_sync_candidate(tokens: []const lexer.Token) bool {
    // Only the statically-unrolled field getter shape has typed GC lowering.
    // Other reflection forms remain on ARC until their metadata/runtime
    // boundary is admitted explicitly.
    if (tokens_have_field_reflection(tokens) and !tokens_have_gc_sync_field_reflection(tokens)) return false;
    // `recv` binds loop locals through a source collection protocol. The
    // synchronous GC emitter currently lowers only direct collection loops;
    // selecting it for a recv loop would leave the bound value uninitialized.
    if (tokens_have_recv_loop_source(tokens)) return false;
    const has_managed_struct_decl = tokens_have_managed_struct_declaration(tokens);
    var found_candidate = false;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "(") or
            !is_top_level_decl_head(tokens, i)) continue;
        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        const body_open = find_top_level_block_open(tokens, close_params + 1, tokens.len) orelse {
            i = close_params;
            continue;
        };
        const body_close = find_matching(tokens, body_open, "{", "}") catch {
            i = body_open;
            continue;
        };
        // GC emission collects every visible function. If any declaration
        // has an unsupported parameter/result shape, admitting only a
        // neighboring managed declaration would make the whole-program route
        // fail after selection. Reject the candidate before emission instead.
        const has_scalar_union_result = gc_sync_header_has_scalar_union_result(tokens, i + 1, body_open);
        const has_managed_union_result = gc_sync_header_has_managed_union_result(tokens, i + 1, body_open);
        const has_unmanaged_struct_result = gc_sync_header_has_unmanaged_struct_result(tokens, i + 1, body_open);
        const has_inline_scalar_struct_result = has_unmanaged_struct_result and
            gc_sync_header_has_inline_scalar_struct_result(tokens, i + 1, body_open);
        if (has_managed_union_result and body_has_gc_sync_managed_union_unsupported_shape(tokens, 0, tokens.len)) return false;
        if (gc_sync_header_has_unsupported_shape(tokens, i + 1, body_open) or
            (has_unmanaged_struct_result and !has_inline_scalar_struct_result and !has_scalar_union_result and !has_managed_union_result)) return false;
        var header_candidate = false;
        const bounded_multi_result = gc_sync_header_has_bounded_multi_result(tokens, i + 1, body_open);
        const managed_struct_multi_result = gc_sync_header_has_managed_struct_multi_result(tokens, i + 1, body_open);
        if (bounded_multi_result) {
            // The admitted multi-result slice is limited to direct scalar or
            // bounded [u8] values. A single [u8] parameter is supported by the
            // GC body emitter; additional or non-managed parameters remain on
            // the legacy route until their root plan is explicit.
            const has_single_managed_param = gc_sync_header_has_single_bounded_managed_param(tokens, i + 1, body_open);
            if ((close_params != i + 2 and !has_single_managed_param) or
                !body_has_gc_sync_scalar_multi_result_return(tokens, body_open + 1, body_close)) return false;
            header_candidate = true;
        } else if (managed_struct_multi_result) {
            // Managed-struct multi-result carriers still require the original
            // no-parameter boundary; their parameter root plan is separate.
            if (close_params != i + 2 or
                !body_has_gc_sync_scalar_multi_result_return(tokens, body_open + 1, body_close)) return false;
            header_candidate = true;
        }
        if (has_inline_scalar_struct_result) {
            const has_single_managed_param = gc_sync_header_has_single_bounded_managed_param(tokens, i + 1, body_open);
            if (!has_single_managed_param or
                !body_has_gc_sync_inline_scalar_struct_result(tokens, body_open + 1, body_close)) return false;
            header_candidate = true;
        }
        if (has_scalar_union_result or has_managed_union_result) header_candidate = true;
        for (tokens[i..body_open]) |token| {
            if (token.kind == .ident and std.mem.eql(u8, token.lexeme, "text")) header_candidate = true;
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "[")) header_candidate = true;
            if (has_managed_struct_decl and token.kind == .ident and
                is_declared_type_name(token.lexeme) and struct_name_is_managed(tokens, token.lexeme, 0)) header_candidate = true;
        }
        // Inspect the complete declaration header. Parameter unions and
        // unsupported resource/result forms must stay on the legacy route;
        // checking only the result suffix misclassifies `text | nil` inputs.
        // An admitted managed local is part of the module's source-value data
        // flow even when the function signature is scalar-only. Select GC only
        // for the bounded body shapes handled below; other body shapes remain
        // on their existing route until their migration gate closes.
        if (header_candidate or body_has_gc_sync_managed_binding(tokens, body_open + 1, body_close)) found_candidate = true;
        i = body_close;
    }
    if (found_candidate and tokens_have_multiple_managed_gets_in_call(tokens)) return false;
    return found_candidate;
}

fn body_has_gc_sync_scalar_multi_result_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_end <= i) return false;
        if (tok_eq(tokens[i], "if") or tok_eq(tokens[i], "loop")) return false;
        if (tok_eq(tokens[i], "defer")) {
            if (i + 3 >= stmt_end or tokens[i + 1].kind != .ident or !tok_eq(tokens[i + 2], "(")) return false;
            const close_idx = find_matching_in_range(tokens, i + 2, "(", ")", stmt_end) catch return false;
            if (close_idx + 1 != stmt_end or close_idx != i + 3) return false;
            i = stmt_end;
            continue;
        }
        if (tok_eq(tokens[i], "return")) {
            if (find_top_level_token(tokens, i + 1, stmt_end, ",") != null) return true;
            if (i + 3 < stmt_end and tokens[i + 1].kind == .ident and tok_eq(tokens[i + 2], "(")) {
                const close_idx = find_matching_in_range(tokens, i + 2, "(", ")", stmt_end) catch return false;
                if (close_idx + 1 == stmt_end) return true;
            }
        }
        i = stmt_end;
    }
    return false;
}

fn tokens_have_recv_loop_source(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, index| {
        if (!tok_eq(token, "recv") or index + 1 >= tokens.len) continue;
        if (tok_eq(tokens[index + 1], "(")) return true;
    }
    return false;
}

fn body_has_gc_sync_managed_binding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (body_has_gc_sync_managed_struct_storage_update(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_managed_struct_alias(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_managed_struct_field_read(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_fallthrough(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_alias(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_overwrite(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_local_overwrite(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_block_return(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_if_else_return(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_else_if_return(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_branch_local_return(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_branch_local_fallthrough(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_nested_byte_list_fallthrough(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_loop_return(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_cross_scope_break(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_loop_break(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_cross_scope_continue(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_loop_continue(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_byte_list_guard_return(tokens, start_idx, end_idx)) return true;
    if (body_has_gc_sync_inferred_scalar_list_put(tokens, start_idx, end_idx)) return true;
    var found_text_binding = false;
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const stmt_end = find_stmt_end(tokens, i, end_idx);

        // Explicit `name text = ...` bindings are admitted by the existing
        // body emitter. Managed structs are admitted separately only for the
        // bounded constructor plus scalar-field update shape below; other
        // storage/control-flow forms stay on their current route.
        if (tokens[i + 1].kind == .ident) {
            const ty = tokens[i + 1].lexeme;
            if (std.mem.eql(u8, ty, "text")) {
                const eq_idx = find_top_level_token(tokens, i + 2, stmt_end, "=") orelse continue;
                if (eq_idx + 1 < stmt_end and tokens[eq_idx + 1].kind == .string) found_text_binding = true;
            }
        }

        // The GC body emitter already has complete bounded literal and
        // copy/set paths for a standalone scalar list. Keep admission
        // deliberately narrow until the surrounding storage/loop operations
        // have their own root plan.
        if (i == start_idx and tok_eq(tokens[i + 1], "[")) {
            const close_type = find_matching_in_range(tokens, i + 1, "[", "]", stmt_end) catch continue;
            if (close_type == i + 3 and tokens[i + 2].kind == .ident and
                type_util.is_core_wasm_scalar(tokens[i + 2].lexeme))
            {
                const eq_idx = find_top_level_token(tokens, close_type + 1, stmt_end, "=") orelse continue;
                if (eq_idx + 2 < stmt_end and tok_eq(tokens[eq_idx + 1], ".") and tok_eq(tokens[eq_idx + 2], "{") and
                    body_has_gc_sync_scalar_list_read(tokens, start_idx, end_idx, stmt_end))
                {
                    return true;
                }
                if (eq_idx + 2 < stmt_end and tok_eq(tokens[eq_idx + 1], ".") and tok_eq(tokens[eq_idx + 2], "{") and
                    body_has_gc_sync_scalar_list_put(tokens, start_idx, end_idx, stmt_end))
                {
                    return true;
                }
                if (eq_idx + 2 < stmt_end and tok_eq(tokens[eq_idx + 1], ".") and tok_eq(tokens[eq_idx + 2], "{") and
                    body_has_gc_sync_scalar_list_set(tokens, start_idx, end_idx, stmt_end))
                {
                    return true;
                }
                if (eq_idx + 2 < stmt_end and tok_eq(tokens[eq_idx + 1], ".") and tok_eq(tokens[eq_idx + 2], "{") and
                    stmt_end < end_idx and tok_eq(tokens[stmt_end], "return") and find_stmt_end(tokens, stmt_end, end_idx) == end_idx)
                {
                    return true;
                }
            }
        }
    }
    if (!found_text_binding) return false;
    // `@len(text)` is still validated by the legacy storage/type path. Keep
    // that body on ARC until the corresponding text intrinsic lowering closes.
    var j = start_idx;
    while (j + 1 < end_idx) : (j += 1) {
        if (tok_eq(tokens[j], "@") and tok_eq(tokens[j + 1], "len")) return false;
    }
    return true;
}

fn body_has_gc_sync_managed_struct_alias(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=") or
        tokens[start_idx + 5].kind != .string) return false;
    const bytes_end = find_stmt_end(tokens, start_idx, end_idx);
    if (bytes_end + 5 >= end_idx or tokens[bytes_end].kind != .ident or
        tokens[bytes_end + 1].kind != .ident or !tok_eq(tokens[bytes_end + 2], "=") or
        tokens[bytes_end + 3].kind != .ident or !tok_eq(tokens[bytes_end + 4], "{") or
        !std.mem.eql(u8, tokens[bytes_end + 1].lexeme, tokens[bytes_end + 3].lexeme) or
        !struct_name_is_managed(tokens, tokens[bytes_end + 1].lexeme, 0)) return false;
    const ctor_close = find_matching_in_range(tokens, bytes_end + 4, "{", "}", end_idx) catch return false;
    if (ctor_close + 4 >= end_idx or tokens[ctor_close + 1].kind != .ident or
        tokens[ctor_close + 2].kind != .ident or !tok_eq(tokens[ctor_close + 3], "=") or
        !std.mem.eql(u8, tokens[ctor_close + 2].lexeme, tokens[bytes_end + 1].lexeme) or
        std.mem.eql(u8, tokens[ctor_close + 1].lexeme, tokens[bytes_end].lexeme) or
        tokens[ctor_close + 4].kind != .ident or
        !std.mem.eql(u8, tokens[ctor_close + 4].lexeme, tokens[bytes_end].lexeme)) return false;
    const alias_end = find_stmt_end(tokens, ctor_close + 1, end_idx);
    if (alias_end >= end_idx or !tok_eq(tokens[alias_end], "return")) return false;
    return find_stmt_end(tokens, alias_end, end_idx) == end_idx;
}

fn body_has_gc_sync_inferred_scalar_list_put(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var seed_name: ?[]const u8 = null;
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_end <= i) return false;

        if (seed_name == null and tokens[i].kind == .ident and i + 3 < stmt_end and tok_eq(tokens[i + 1], "[") and
            tokens[i + 2].kind == .ident and
            (std.mem.eql(u8, tokens[i + 2].lexeme, "u8") or std.mem.eql(u8, tokens[i + 2].lexeme, "u32")) and
            tok_eq(tokens[i + 3], "]"))
        {
            const eq_idx = find_top_level_token(tokens, i + 4, stmt_end, "=") orelse return false;
            if (eq_idx + 2 >= stmt_end or !tok_eq(tokens[eq_idx + 1], ".") or !tok_eq(tokens[eq_idx + 2], "{")) return false;
            const close_brace = find_matching_in_range(tokens, eq_idx + 2, "{", "}", stmt_end) catch return false;
            if (close_brace + 1 != stmt_end) return false;
            seed_name = tokens[i].lexeme;
            i = stmt_end;
            continue;
        }

        if (seed_name) |seed| {
            if (tokens[i].kind != .ident or i + 4 >= stmt_end or !tok_eq(tokens[i + 1], "=") or
                !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "put") or !tok_eq(tokens[i + 4], "(")) return false;
            const close_idx = find_matching_in_range(tokens, i + 4, "(", ")", stmt_end) catch return false;
            if (close_idx + 1 != stmt_end) return false;
            const receiver_end = find_arg_end(tokens, i + 5, close_idx);
            if (receiver_end != i + 6 or receiver_end >= close_idx or !tok_eq(tokens[receiver_end], ",") or
                tokens[i + 5].kind != .ident or !std.mem.eql(u8, tokens[i + 5].lexeme, seed)) return false;
            const value_start = receiver_end + 1;
            const value_end = find_arg_end(tokens, value_start, close_idx);
            if (value_end != close_idx or value_end != value_start + 1 or tokens[value_start].kind != .number) return false;
            if (stmt_end >= end_idx or !tok_eq(tokens[stmt_end], "return") or find_stmt_end(tokens, stmt_end, end_idx) != end_idx) return false;
            return true;
        }

        return false;
    }
    return false;
}

fn body_has_gc_sync_byte_list_fallthrough(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=")) return false;
    const stmt_end = find_stmt_end(tokens, start_idx, end_idx);
    return stmt_end == end_idx and stmt_end == start_idx + 6 and tokens[start_idx + 5].kind == .string;
}

fn body_has_gc_sync_byte_list_alias(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=") or
        tokens[start_idx + 5].kind != .string) return false;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end + 5 >= end_idx or tokens[first_end].kind != .ident or
        !tok_eq(tokens[first_end + 1], "[") or !tok_eq(tokens[first_end + 2], "u8") or
        !tok_eq(tokens[first_end + 3], "]") or !tok_eq(tokens[first_end + 4], "=") or
        tokens[first_end + 5].kind != .ident or
        std.mem.eql(u8, tokens[first_end].lexeme, tokens[start_idx].lexeme) or
        !std.mem.eql(u8, tokens[first_end + 5].lexeme, tokens[start_idx].lexeme)) return false;
    const alias_end = find_stmt_end(tokens, first_end, end_idx);
    if (alias_end != first_end + 6 or alias_end >= end_idx or !tok_eq(tokens[alias_end], "return")) return false;
    return find_stmt_end(tokens, alias_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_overwrite(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=")) return false;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 6 or tokens[start_idx + 5].kind != .string) return false;
    if (first_end >= end_idx or tokens[first_end].kind != .ident or
        !std.mem.eql(u8, tokens[first_end].lexeme, tokens[start_idx].lexeme) or
        first_end + 2 >= end_idx or !tok_eq(tokens[first_end + 1], "=") or
        tokens[first_end + 2].kind != .string) return false;
    const assignment_end = find_stmt_end(tokens, first_end, end_idx);
    if (assignment_end != first_end + 3) return false;
    if (assignment_end >= end_idx or !tok_eq(tokens[assignment_end], "return")) return false;
    return find_stmt_end(tokens, assignment_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_local_overwrite(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=") or
        tokens[start_idx + 5].kind != .string) return false;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end + 5 >= end_idx or tokens[first_end].kind != .ident or
        !tok_eq(tokens[first_end + 1], "[") or !tok_eq(tokens[first_end + 2], "u8") or
        !tok_eq(tokens[first_end + 3], "]") or !tok_eq(tokens[first_end + 4], "=") or
        tokens[first_end + 5].kind != .string or
        std.mem.eql(u8, tokens[first_end].lexeme, tokens[start_idx].lexeme)) return false;
    const second_end = find_stmt_end(tokens, first_end, end_idx);
    if (second_end + 3 >= end_idx or tokens[second_end].kind != .ident or
        !std.mem.eql(u8, tokens[second_end].lexeme, tokens[start_idx].lexeme) or
        !tok_eq(tokens[second_end + 1], "=") or tokens[second_end + 2].kind != .ident or
        !std.mem.eql(u8, tokens[second_end + 2].lexeme, tokens[first_end].lexeme)) return false;
    const assignment_end = find_stmt_end(tokens, second_end, end_idx);
    if (assignment_end != second_end + 3 or assignment_end >= end_idx or !tok_eq(tokens[assignment_end], "return")) return false;
    return find_stmt_end(tokens, assignment_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_guard_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=")) return false;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 6 or tokens[start_idx + 5].kind != .string) return false;
    if (first_end + 3 >= end_idx or tokens[first_end].kind != .ident or
        !tok_eq(tokens[first_end + 1], "bool") or !tok_eq(tokens[first_end + 2], "=") or
        (!tok_eq(tokens[first_end + 3], "true") and !tok_eq(tokens[first_end + 3], "false"))) return false;
    const bool_end = find_stmt_end(tokens, first_end, end_idx);
    if (bool_end != first_end + 4 or bool_end + 3 >= end_idx or !tok_eq(tokens[bool_end], "if") or
        tokens[bool_end + 1].kind != .ident or !tok_eq(tokens[bool_end + 2], "return")) return false;
    const guard_end = find_stmt_end(tokens, bool_end, end_idx);
    if (guard_end != bool_end + 3 or guard_end >= end_idx or !tok_eq(tokens[guard_end], "return")) return false;
    return find_stmt_end(tokens, guard_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_block_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=")) return false;
    const data_name = tokens[start_idx].lexeme;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 6 or tokens[start_idx + 5].kind != .string) return false;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], "if")) return false;

    const if_end = find_stmt_end(tokens, first_end, end_idx);
    const open_idx = find_top_level_block_open(tokens, first_end + 1, if_end) orelse return false;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", if_end) catch return false;
    if (close_idx + 1 != if_end or close_idx != open_idx + 2 or !tok_eq(tokens[open_idx + 1], "return")) return false;

    // Keep the admission limited to the length comparison already supported
    // by the typed GC expression emitter.
    const condition_start = first_end + 1;
    if (open_idx != condition_start + 11 or
        !tok_eq(tokens[condition_start], "@") or !tok_eq(tokens[condition_start + 1], "eq") or
        !tok_eq(tokens[condition_start + 2], "(") or !tok_eq(tokens[condition_start + 3], "@") or
        !tok_eq(tokens[condition_start + 4], "len") or !tok_eq(tokens[condition_start + 5], "(") or
        tokens[condition_start + 6].kind != .ident or
        !std.mem.eql(u8, tokens[condition_start + 6].lexeme, data_name) or
        !tok_eq(tokens[condition_start + 7], ")") or !tok_eq(tokens[condition_start + 8], ",") or
        tokens[condition_start + 9].kind != .number or !tok_eq(tokens[condition_start + 10], ")")) return false;

    if (if_end >= end_idx or !tok_eq(tokens[if_end], "return")) return false;
    return find_stmt_end(tokens, if_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_branch_local_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return false;
    const if_end = find_stmt_end(tokens, start_idx, end_idx);
    const open_idx = find_top_level_block_open(tokens, start_idx + 1, if_end) orelse return false;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", if_end) catch return false;
    if (close_idx + 1 != if_end or open_idx != start_idx + 8) return false;
    if (!tok_eq(tokens[start_idx + 1], "@") or !tok_eq(tokens[start_idx + 2], "eq") or
        !tok_eq(tokens[start_idx + 3], "(") or tokens[start_idx + 4].kind != .number or
        !tok_eq(tokens[start_idx + 5], ",") or tokens[start_idx + 6].kind != .number or
        !tok_eq(tokens[start_idx + 7], ")")) return false;

    const local_start = open_idx + 1;
    const local_end = find_stmt_end(tokens, local_start, close_idx);
    if (local_end <= local_start or local_end >= close_idx or tokens[local_start].kind != .ident or
        !tok_eq(tokens[local_start + 1], "[") or !tok_eq(tokens[local_start + 2], "u8") or
        !tok_eq(tokens[local_start + 3], "]") or !tok_eq(tokens[local_start + 4], "=") or
        tokens[local_start + 5].kind != .string) return false;
    if (local_end >= close_idx or !tok_eq(tokens[local_end], "return") or
        find_stmt_end(tokens, local_end, close_idx) != close_idx) return false;
    if (if_end >= end_idx or !tok_eq(tokens[if_end], "return")) return false;
    return find_stmt_end(tokens, if_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_branch_local_fallthrough(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return false;
    const if_end = find_stmt_end(tokens, start_idx, end_idx);
    const open_idx = find_top_level_block_open(tokens, start_idx + 1, if_end) orelse return false;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", if_end) catch return false;
    if (close_idx + 1 != if_end or open_idx != start_idx + 8) return false;
    if (!tok_eq(tokens[start_idx + 1], "@") or !tok_eq(tokens[start_idx + 2], "eq") or
        !tok_eq(tokens[start_idx + 3], "(") or tokens[start_idx + 4].kind != .number or
        !tok_eq(tokens[start_idx + 5], ",") or tokens[start_idx + 6].kind != .number or
        !tok_eq(tokens[start_idx + 7], ")")) return false;

    const local_start = open_idx + 1;
    const local_end = find_stmt_end(tokens, local_start, close_idx);
    if (local_end != close_idx or tokens[local_start].kind != .ident or
        !tok_eq(tokens[local_start + 1], "[") or !tok_eq(tokens[local_start + 2], "u8") or
        !tok_eq(tokens[local_start + 3], "]") or !tok_eq(tokens[local_start + 4], "=") or
        tokens[local_start + 5].kind != .string) return false;
    if (if_end >= end_idx or !tok_eq(tokens[if_end], "return")) return false;
    return find_stmt_end(tokens, if_end, end_idx) == end_idx;
}

fn body_has_gc_sync_nested_byte_list_fallthrough(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return false;
    const outer_end = find_stmt_end(tokens, start_idx, end_idx);
    const outer_open = find_top_level_block_open(tokens, start_idx + 1, outer_end) orelse return false;
    const outer_close = find_matching_in_range(tokens, outer_open, "{", "}", outer_end) catch return false;
    if (outer_close + 1 != outer_end or outer_close <= outer_open + 1) return false;

    // The outer condition is the scalar numeric equality already emitted by
    // the typed GC expression path.
    if (outer_open != start_idx + 8 or
        !tok_eq(tokens[start_idx + 1], "@") or !tok_eq(tokens[start_idx + 2], "eq") or
        !tok_eq(tokens[start_idx + 3], "(") or tokens[start_idx + 4].kind != .number or
        !tok_eq(tokens[start_idx + 5], ",") or tokens[start_idx + 6].kind != .number or
        !tok_eq(tokens[start_idx + 7], ")")) return false;

    const outer_local = outer_open + 1;
    const outer_local_end = find_stmt_end(tokens, outer_local, outer_close);
    if (outer_local + 5 >= outer_close or outer_local_end + 1 >= outer_close or tokens[outer_local].kind != .ident or
        !tok_eq(tokens[outer_local + 1], "[") or !tok_eq(tokens[outer_local + 2], "u8") or
        !tok_eq(tokens[outer_local + 3], "]") or !tok_eq(tokens[outer_local + 4], "=") or
        tokens[outer_local + 5].kind != .string) return false;

    const nested_if = outer_local_end;
    if (!tok_eq(tokens[nested_if], "if")) return false;
    const nested_end = find_stmt_end(tokens, nested_if, outer_close);
    const nested_open = find_top_level_block_open(tokens, nested_if + 1, nested_end) orelse return false;
    const nested_close = find_matching_in_range(tokens, nested_open, "{", "}", nested_end) catch return false;
    if (nested_close + 1 != nested_end or nested_close != nested_open + 7 or
        nested_open != nested_if + 8 or
        !tok_eq(tokens[nested_if + 1], "@") or !tok_eq(tokens[nested_if + 2], "eq") or
        !tok_eq(tokens[nested_if + 3], "(") or tokens[nested_if + 4].kind != .number or
        !tok_eq(tokens[nested_if + 5], ",") or tokens[nested_if + 6].kind != .number or
        !tok_eq(tokens[nested_if + 7], ")")) return false;

    const nested_local = nested_open + 1;
    const nested_local_end = find_stmt_end(tokens, nested_local, nested_close);
    if (nested_local + 5 >= nested_close or nested_local_end != nested_close or tokens[nested_local].kind != .ident or
        !tok_eq(tokens[nested_local + 1], "[") or !tok_eq(tokens[nested_local + 2], "u8") or
        !tok_eq(tokens[nested_local + 3], "]") or !tok_eq(tokens[nested_local + 4], "=") or
        tokens[nested_local + 5].kind != .string) return false;

    if (outer_end >= end_idx or !tok_eq(tokens[outer_end], "return")) return false;
    return find_stmt_end(tokens, outer_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_loop_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=") or
        tokens[start_idx + 5].kind != .string) return false;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end >= end_idx or !tok_eq(tokens[first_end], "loop")) return false;
    const loop_end = find_stmt_end(tokens, first_end, end_idx);
    const open_idx = find_top_level_block_open(tokens, first_end + 1, loop_end) orelse return false;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", loop_end) catch return false;
    if (close_idx + 1 != loop_end or close_idx != open_idx + 2 or !tok_eq(tokens[open_idx + 1], "return")) return false;
    return loop_end == end_idx;
}

fn body_has_gc_sync_byte_list_loop_break(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "loop")) return false;
    const loop_end = find_stmt_end(tokens, start_idx, end_idx);
    const open_idx = find_top_level_block_open(tokens, start_idx + 1, loop_end) orelse return false;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", loop_end) catch return false;
    if (close_idx + 1 != loop_end) return false;

    const local_start = open_idx + 1;
    const local_end = find_stmt_end(tokens, local_start, close_idx);
    if (local_end >= close_idx or tokens[local_start].kind != .ident or
        !tok_eq(tokens[local_start + 1], "[") or !tok_eq(tokens[local_start + 2], "u8") or
        !tok_eq(tokens[local_start + 3], "]") or !tok_eq(tokens[local_start + 4], "=") or
        tokens[local_start + 5].kind != .string or !tok_eq(tokens[local_end], "break") or
        find_stmt_end(tokens, local_end, close_idx) != close_idx) return false;
    if (loop_end >= end_idx or !tok_eq(tokens[loop_end], "return")) return false;
    return find_stmt_end(tokens, loop_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_cross_scope_break(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    // Bounded migration slice for a labeled break that crosses exactly one
    // nested loop. Both loops have one byte-list local and no deferred or
    // conditional control, so the GC emitter can preserve the target block
    // without needing a general control-flow cleanup plan yet.
    if (start_idx + 2 >= end_idx or !tok_eq(tokens[start_idx], "#") or
        tokens[start_idx + 1].kind != .ident or !tok_eq(tokens[start_idx + 2], "loop")) return false;
    const outer_label = tokens[start_idx + 1].lexeme;
    const outer_loop = start_idx + 2;
    if (codegen_control_flow.label_for_loop_start(tokens, outer_loop)) |label| {
        if (!std.mem.eql(u8, label, outer_label)) return false;
    } else return false;

    const outer_end = find_stmt_end(tokens, outer_loop, end_idx);
    const outer_open = find_top_level_block_open(tokens, outer_loop + 1, outer_end) orelse return false;
    const outer_close = find_matching_in_range(tokens, outer_open, "{", "}", outer_end) catch return false;
    if (outer_close + 1 != outer_end) return false;

    const outer_local = outer_open + 1;
    const outer_local_end = find_stmt_end(tokens, outer_local, outer_close);
    if (outer_local + 5 >= outer_close or outer_local_end >= outer_close or tokens[outer_local].kind != .ident or
        !tok_eq(tokens[outer_local + 1], "[") or !tok_eq(tokens[outer_local + 2], "u8") or
        !tok_eq(tokens[outer_local + 3], "]") or !tok_eq(tokens[outer_local + 4], "=") or
        tokens[outer_local + 5].kind != .string) return false;

    const inner_loop = outer_local_end;
    if (!tok_eq(tokens[inner_loop], "loop")) return false;
    const inner_end = find_stmt_end(tokens, inner_loop, outer_close);
    const inner_open = find_top_level_block_open(tokens, inner_loop + 1, inner_end) orelse return false;
    const inner_close = find_matching_in_range(tokens, inner_open, "{", "}", inner_end) catch return false;
    if (inner_close + 1 != inner_end or inner_close <= inner_open + 1) return false;

    const inner_local = inner_open + 1;
    const inner_local_end = find_stmt_end(tokens, inner_local, inner_close);
    if (inner_local + 5 >= inner_close or inner_local_end >= inner_close or tokens[inner_local].kind != .ident or
        !tok_eq(tokens[inner_local + 1], "[") or !tok_eq(tokens[inner_local + 2], "u8") or
        !tok_eq(tokens[inner_local + 3], "]") or !tok_eq(tokens[inner_local + 4], "=") or
        tokens[inner_local + 5].kind != .string or !tok_eq(tokens[inner_local_end], "break") or
        inner_local_end + 3 != inner_close or !tok_eq(tokens[inner_local_end + 1], "#") or
        tokens[inner_local_end + 2].kind != .ident or
        !std.mem.eql(u8, tokens[inner_local_end + 2].lexeme, outer_label)) return false;

    if (outer_end >= end_idx or !tok_eq(tokens[outer_end], "return")) return false;
    return find_stmt_end(tokens, outer_end, end_idx) == end_idx;
}

fn body_has_gc_sync_byte_list_cross_scope_continue(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    // Bounded sibling of the labeled-break slice above. The continue target
    // is the enclosing loop's label; no code follows the outer loop in this
    // admitted shape, so no fallthrough cleanup is needed.
    if (start_idx + 2 >= end_idx or !tok_eq(tokens[start_idx], "#") or
        tokens[start_idx + 1].kind != .ident or !tok_eq(tokens[start_idx + 2], "loop")) return false;
    const outer_label = tokens[start_idx + 1].lexeme;
    const outer_loop = start_idx + 2;
    if (codegen_control_flow.label_for_loop_start(tokens, outer_loop)) |label| {
        if (!std.mem.eql(u8, label, outer_label)) return false;
    } else return false;

    const outer_end = find_stmt_end(tokens, outer_loop, end_idx);
    const outer_open = find_top_level_block_open(tokens, outer_loop + 1, outer_end) orelse return false;
    const outer_close = find_matching_in_range(tokens, outer_open, "{", "}", outer_end) catch return false;
    if (outer_close + 1 != outer_end) return false;

    const outer_local = outer_open + 1;
    const outer_local_end = find_stmt_end(tokens, outer_local, outer_close);
    if (outer_local + 5 >= outer_close or outer_local_end >= outer_close or tokens[outer_local].kind != .ident or
        !tok_eq(tokens[outer_local + 1], "[") or !tok_eq(tokens[outer_local + 2], "u8") or
        !tok_eq(tokens[outer_local + 3], "]") or !tok_eq(tokens[outer_local + 4], "=") or
        tokens[outer_local + 5].kind != .string) return false;

    const inner_loop = outer_local_end;
    if (!tok_eq(tokens[inner_loop], "loop")) return false;
    const inner_end = find_stmt_end(tokens, inner_loop, outer_close);
    const inner_open = find_top_level_block_open(tokens, inner_loop + 1, inner_end) orelse return false;
    const inner_close = find_matching_in_range(tokens, inner_open, "{", "}", inner_end) catch return false;
    if (inner_close + 1 != inner_end or inner_close <= inner_open + 1) return false;

    const inner_local = inner_open + 1;
    const inner_local_end = find_stmt_end(tokens, inner_local, inner_close);
    if (inner_local + 5 >= inner_close or inner_local_end >= inner_close or tokens[inner_local].kind != .ident or
        !tok_eq(tokens[inner_local + 1], "[") or !tok_eq(tokens[inner_local + 2], "u8") or
        !tok_eq(tokens[inner_local + 3], "]") or !tok_eq(tokens[inner_local + 4], "=") or
        tokens[inner_local + 5].kind != .string or !tok_eq(tokens[inner_local_end], "continue") or
        inner_local_end + 3 != inner_close or !tok_eq(tokens[inner_local_end + 1], "#") or
        tokens[inner_local_end + 2].kind != .ident or
        !std.mem.eql(u8, tokens[inner_local_end + 2].lexeme, outer_label)) return false;

    return outer_end == end_idx;
}

fn body_has_gc_sync_byte_list_loop_continue(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "loop")) return false;
    const loop_end = find_stmt_end(tokens, start_idx, end_idx);
    const open_idx = find_top_level_block_open(tokens, start_idx + 1, loop_end) orelse return false;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", loop_end) catch return false;
    if (close_idx + 1 != loop_end) return false;

    const local_start = open_idx + 1;
    const local_end = find_stmt_end(tokens, local_start, close_idx);
    if (local_end >= close_idx or tokens[local_start].kind != .ident or
        !tok_eq(tokens[local_start + 1], "[") or !tok_eq(tokens[local_start + 2], "u8") or
        !tok_eq(tokens[local_start + 3], "]") or !tok_eq(tokens[local_start + 4], "=") or
        tokens[local_start + 5].kind != .string or !tok_eq(tokens[local_end], "continue") or
        find_stmt_end(tokens, local_end, close_idx) != close_idx) return false;
    return loop_end == end_idx;
}

fn body_has_gc_sync_byte_list_if_else_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=")) return false;
    const data_name = tokens[start_idx].lexeme;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 6 or tokens[start_idx + 5].kind != .string) return false;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], "if")) return false;

    const if_end = find_stmt_end(tokens, first_end, end_idx);
    const open_idx = find_top_level_block_open(tokens, first_end + 1, if_end) orelse return false;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", if_end) catch return false;
    if (close_idx + 1 >= if_end or !tok_eq(tokens[close_idx + 1], "else") or
        close_idx != open_idx + 2 or !tok_eq(tokens[open_idx + 1], "return")) return false;

    const else_open = find_top_level_block_open(tokens, close_idx + 2, if_end) orelse return false;
    const else_close = find_matching_in_range(tokens, else_open, "{", "}", if_end) catch return false;
    if (else_close + 1 != if_end or else_close != else_open + 2 or !tok_eq(tokens[else_open + 1], "return")) return false;

    // Keep admission limited to the length comparison already supported by the
    // typed GC expression emitter.
    const condition_start = first_end + 1;
    if (open_idx != condition_start + 11 or
        !tok_eq(tokens[condition_start], "@") or !tok_eq(tokens[condition_start + 1], "eq") or
        !tok_eq(tokens[condition_start + 2], "(") or !tok_eq(tokens[condition_start + 3], "@") or
        !tok_eq(tokens[condition_start + 4], "len") or !tok_eq(tokens[condition_start + 5], "(") or
        tokens[condition_start + 6].kind != .ident or
        !std.mem.eql(u8, tokens[condition_start + 6].lexeme, data_name) or
        !tok_eq(tokens[condition_start + 7], ")") or !tok_eq(tokens[condition_start + 8], ",") or
        tokens[condition_start + 9].kind != .number or !tok_eq(tokens[condition_start + 10], ")")) return false;

    return true;
}

fn gc_sync_byte_list_length_condition(
    tokens: []const lexer.Token,
    condition_start: usize,
    block_open: usize,
    data_name: []const u8,
) bool {
    if (block_open != condition_start + 11 or
        !tok_eq(tokens[condition_start], "@") or !tok_eq(tokens[condition_start + 1], "eq") or
        !tok_eq(tokens[condition_start + 2], "(") or !tok_eq(tokens[condition_start + 3], "@") or
        !tok_eq(tokens[condition_start + 4], "len") or !tok_eq(tokens[condition_start + 5], "(") or
        tokens[condition_start + 6].kind != .ident or
        !std.mem.eql(u8, tokens[condition_start + 6].lexeme, data_name) or
        !tok_eq(tokens[condition_start + 7], ")") or !tok_eq(tokens[condition_start + 8], ",") or
        tokens[condition_start + 9].kind != .number or !tok_eq(tokens[condition_start + 10], ")")) return false;
    return true;
}

fn gc_sync_byte_list_return_block(tokens: []const lexer.Token, open_idx: usize, close_idx: usize) bool {
    return close_idx == open_idx + 2 and tok_eq(tokens[open_idx + 1], "return");
}

fn body_has_gc_sync_byte_list_else_if_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "[") or !tok_eq(tokens[start_idx + 2], "u8") or
        !tok_eq(tokens[start_idx + 3], "]") or !tok_eq(tokens[start_idx + 4], "=")) return false;
    const data_name = tokens[start_idx].lexeme;
    const first_end = find_stmt_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 6 or tokens[start_idx + 5].kind != .string) return false;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], "if")) return false;

    const first_if_end = find_stmt_end(tokens, first_end, end_idx);
    const first_open = find_top_level_block_open(tokens, first_end + 1, first_if_end) orelse return false;
    const first_close = find_matching_in_range(tokens, first_open, "{", "}", first_if_end) catch return false;
    if (first_close + 1 >= first_if_end or !tok_eq(tokens[first_close + 1], "else") or
        !gc_sync_byte_list_return_block(tokens, first_open, first_close) or
        !tok_eq(tokens[first_close + 2], "if")) return false;
    if (!gc_sync_byte_list_length_condition(tokens, first_end + 1, first_open, data_name)) return false;

    const nested_if = first_close + 2;
    const nested_open = find_top_level_block_open(tokens, nested_if + 1, first_if_end) orelse return false;
    const nested_close = find_matching_in_range(tokens, nested_open, "{", "}", first_if_end) catch return false;
    if (nested_close + 1 >= first_if_end or !tok_eq(tokens[nested_close + 1], "else") or
        !gc_sync_byte_list_return_block(tokens, nested_open, nested_close) or
        !gc_sync_byte_list_length_condition(tokens, nested_if + 1, nested_open, data_name)) return false;

    const final_open = find_top_level_block_open(tokens, nested_close + 2, first_if_end) orelse return false;
    const final_close = find_matching_in_range(tokens, final_open, "{", "}", first_if_end) catch return false;
    if (final_close + 1 != first_if_end or !gc_sync_byte_list_return_block(tokens, final_open, final_close)) return false;
    return true;
}

fn body_has_gc_sync_managed_struct_field_read(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var ctor_names: [16][]const u8 = undefined;
    var ctor_types: [16][]const u8 = undefined;
    var ctor_count: usize = 0;
    var getter_count: usize = 0;
    var found_field_read = false;
    for (tokens[start_idx..end_idx]) |token| {
        if (std.mem.eql(u8, token.lexeme, "defer") or std.mem.eql(u8, token.lexeme, "loop") or
            std.mem.eql(u8, token.lexeme, "if") or std.mem.eql(u8, token.lexeme, "else")) return false;
    }
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_end <= i) continue;
        const at_stmt_start = i == start_idx or tokens[i - 1].line != tokens[i].line;
        if (at_stmt_start and i + 1 < stmt_end and tok_eq(tokens[i + 1], "=")) return false;
        if (tokens[i].kind == .ident and i + 2 < stmt_end and tokens[i + 1].kind == .ident) {
            const local_ty = tokens[i + 1].lexeme;
            if (is_declared_type_name(local_ty) and struct_name_is_managed(tokens, local_ty, 0)) {
                if (find_top_level_token(tokens, i + 2, stmt_end, "=")) |eq_idx| {
                    if (eq_idx + 2 < stmt_end and tokens[eq_idx + 1].kind == .ident and
                        std.mem.eql(u8, tokens[eq_idx + 1].lexeme, local_ty) and tok_eq(tokens[eq_idx + 2], "{") and
                        ctor_count < ctor_names.len)
                    {
                        ctor_names[ctor_count] = tokens[i].lexeme;
                        ctor_types[ctor_count] = local_ty;
                        ctor_count += 1;
                    }
                }
            }
        }

        if (tokens[i].kind != .ident or i + 4 >= stmt_end or tokens[i + 1].kind != .symbol or
            !tok_eq(tokens[i + 1], "[") or !tok_eq(tokens[i + 2], "u8") or
            !tok_eq(tokens[i + 3], "]") or !tok_eq(tokens[i + 4], "=")) continue;
        const lhs_ty = "[u8]";
        const value_start = i + 5;
        if (value_start + 2 >= stmt_end or !tok_eq(tokens[value_start], "@") or
            !tok_eq(tokens[value_start + 1], "get") or !tok_eq(tokens[value_start + 2], "(")) continue;
        const close_idx = find_matching_in_range(tokens, value_start + 2, "(", ")", stmt_end) catch continue;
        if (close_idx + 1 != stmt_end) continue;
        const receiver_end = find_arg_end(tokens, value_start + 3, close_idx);
        if (receiver_end != value_start + 4 or !tok_eq(tokens[receiver_end], ",") or
            tokens[value_start + 3].kind != .ident) continue;
        const field_idx = receiver_end + 1;
        if (field_idx + 1 != close_idx or tokens[field_idx].kind != .ident) continue;
        const field_token = tokens[field_idx];
        if (field_token.lexeme.len < 2 or field_token.lexeme[0] != '.') continue;
        getter_count += 1;
        if (getter_count > 1) return false;
        for (ctor_names[0..ctor_count], 0..) |ctor_name, index| {
            if (!std.mem.eql(u8, ctor_name, tokens[value_start + 3].lexeme)) continue;
            if (!std.mem.eql(u8, lhs_ty, "[u8]")) continue;
            if (struct_has_byte_list_field(tokens, ctor_types[index], field_token.lexeme[1..])) found_field_read = true;
        }
    }
    return getter_count == 1 and found_field_read;
}

fn struct_has_byte_list_field(tokens: []const lexer.Token, struct_name: []const u8, field_name: []const u8) bool {
    const range = find_top_level_struct_range(tokens, struct_name) orelse return false;
    var i = range.open_idx + 1;
    while (i + 3 < range.close_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, field_name)) continue;
        return tok_eq(tokens[i + 1], "[") and tok_eq(tokens[i + 2], "u8") and tok_eq(tokens[i + 3], "]");
    }
    return false;
}

fn body_has_gc_sync_managed_struct_storage_update(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var ctor_name: ?[]const u8 = null;
    var ctor_names: [16][]const u8 = undefined;
    var ctor_count: usize = 0;
    var has_direct_field_set = false;
    var has_direct_managed_alias = false;
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_end <= i) continue;

        if (tokens[i].kind == .ident and i + 1 < stmt_end and tokens[i + 1].kind == .ident) {
            const ty = tokens[i + 1].lexeme;
            if (is_declared_type_name(ty) and struct_name_is_managed(tokens, ty, 0)) {
                if (find_top_level_token(tokens, i + 2, stmt_end, "=")) |eq_idx| {
                    if (eq_idx + 2 < stmt_end and tokens[eq_idx + 1].kind == .ident and
                        std.mem.eql(u8, tokens[eq_idx + 1].lexeme, ty) and tok_eq(tokens[eq_idx + 2], "{"))
                    {
                        if (ctor_name == null) ctor_name = tokens[i].lexeme;
                        if (ctor_count < ctor_names.len) {
                            ctor_names[ctor_count] = tokens[i].lexeme;
                            ctor_count += 1;
                        }
                    }
                }
            }
        }

        if (tokens[i].kind == .ident and i + 2 < stmt_end and tok_eq(tokens[i + 1], "=") and
            tokens[i + 2].kind == .ident)
        {
            for (ctor_names[0..ctor_count]) |name| {
                if (std.mem.eql(u8, tokens[i].lexeme, name)) {
                    has_direct_managed_alias = true;
                    break;
                }
            }
        }

        var j = i;
        while (j + 8 < stmt_end) : (j += 1) {
            if (!tok_eq(tokens[j], "@") or !tok_eq(tokens[j + 1], "set") or !tok_eq(tokens[j + 2], "(")) continue;
            const close_idx = find_matching_in_range(tokens, j + 2, "(", ")", stmt_end) catch continue;
            if (close_idx + 1 != stmt_end) continue;
            const receiver_end = find_arg_end(tokens, j + 3, close_idx);
            if (receiver_end != j + 4 or receiver_end >= close_idx or !tok_eq(tokens[receiver_end], ",") or
                tokens[j + 3].kind != .ident) continue;
            var matches_ctor = false;
            for (ctor_names[0..ctor_count]) |name| {
                if (std.mem.eql(u8, name, tokens[j + 3].lexeme)) {
                    matches_ctor = true;
                    break;
                }
            }
            if (!matches_ctor) continue;
            const field_start = receiver_end + 1;
            const field_end = find_arg_end(tokens, field_start, close_idx);
            if (field_end != field_start + 1 or field_end >= close_idx or tokens[field_start].kind != .ident or
                !tok_eq(tokens[field_end], ",")) continue;
            const value_start = field_end + 1;
            const value_end = find_arg_end(tokens, value_start, close_idx);
            if (value_start + 2 < value_end and tok_eq(tokens[value_start], "@") and
                tok_eq(tokens[value_start + 1], "get") and tok_eq(tokens[value_start + 2], "("))
            {
                const getter_close = find_matching_in_range(tokens, value_start + 2, "(", ")", value_end) catch continue;
                if (getter_close + 1 == value_end) has_direct_field_set = true;
            }
            if (value_end == value_start + 1 and value_start < close_idx and
                (tokens[value_start].kind == .number or
                    (tokens[value_start].kind == .ident and
                        !std.mem.eql(u8, tokens[value_start].lexeme, "nil"))))
            {
                has_direct_field_set = true;
            }
        }
        if (ctor_count != 0 and (has_direct_field_set or has_direct_managed_alias)) return true;
    }
    return false;
}

fn body_has_gc_sync_scalar_list_read(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, first_stmt_end: usize) bool {
    if (start_idx >= first_stmt_end or tokens[start_idx].kind != .ident) return false;
    const list_name = tokens[start_idx].lexeme;
    var saw_len = false;
    var saw_get = false;
    var i = first_stmt_end;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_end <= i) return false;
        if (tok_eq(tokens[i], "return")) return saw_len and saw_get and stmt_end == end_idx;
        var j = i;
        while (j + 1 < stmt_end) : (j += 1) {
            if (!tok_eq(tokens[j], "@") or j + 2 >= stmt_end) continue;
            const intrinsic = tokens[j + 1].lexeme;
            if (!std.mem.eql(u8, intrinsic, "len") and !std.mem.eql(u8, intrinsic, "get")) return false;
            if (!tok_eq(tokens[j + 2], "(")) return false;
            const close = find_matching_in_range(tokens, j + 2, "(", ")", stmt_end) catch return false;
            const first_end = find_arg_end(tokens, j + 3, close);
            if (first_end != j + 4 or tokens[j + 3].kind != .ident or
                !std.mem.eql(u8, tokens[j + 3].lexeme, list_name)) return false;
            if (std.mem.eql(u8, intrinsic, "len")) {
                if (close != first_end) return false;
                saw_len = true;
            } else {
                if (first_end >= close or !tok_eq(tokens[first_end], ",")) return false;
                const index_start = first_end + 1;
                const index_end = find_arg_end(tokens, index_start, close);
                if (index_end != close or index_end != index_start + 1 or tokens[index_start].kind != .number) return false;
                saw_get = true;
            }
            j = close;
        }
        i = stmt_end;
    }
    return false;
}

fn body_has_gc_sync_scalar_list_put(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, first_stmt_end: usize) bool {
    if (start_idx >= first_stmt_end or tokens[start_idx].kind != .ident) return false;
    const list_name = tokens[start_idx].lexeme;
    const assignment_end = find_stmt_end(tokens, first_stmt_end, end_idx);
    if (assignment_end <= first_stmt_end or assignment_end >= end_idx) return false;
    if (tokens[first_stmt_end].kind != .ident or
        !std.mem.eql(u8, tokens[first_stmt_end].lexeme, list_name) or
        first_stmt_end + 4 >= assignment_end or !tok_eq(tokens[first_stmt_end + 1], "=") or
        !tok_eq(tokens[first_stmt_end + 2], "@") or !tok_eq(tokens[first_stmt_end + 3], "put") or
        !tok_eq(tokens[first_stmt_end + 4], "(")) return false;

    const close_idx = find_matching_in_range(tokens, first_stmt_end + 4, "(", ")", assignment_end) catch return false;
    if (close_idx + 1 != assignment_end) return false;
    const receiver_start = first_stmt_end + 5;
    const receiver_end = find_arg_end(tokens, receiver_start, close_idx);
    if (receiver_end >= close_idx or !tok_eq(tokens[receiver_end], ",") or
        receiver_end != receiver_start + 1 or tokens[receiver_start].kind != .ident or
        !std.mem.eql(u8, tokens[receiver_start].lexeme, list_name)) return false;
    const value_start = receiver_end + 1;
    const value_end = find_arg_end(tokens, value_start, close_idx);
    if (value_end != close_idx or value_end != value_start + 1 or tok_eq(tokens[value_start], "...")) return false;
    return tok_eq(tokens[assignment_end], "return") and find_stmt_end(tokens, assignment_end, end_idx) == end_idx;
}

fn body_has_gc_sync_scalar_list_set(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, first_stmt_end: usize) bool {
    if (start_idx >= first_stmt_end or tokens[start_idx].kind != .ident) return false;
    const list_name = tokens[start_idx].lexeme;
    const assignment_end = find_stmt_end(tokens, first_stmt_end, end_idx);
    if (assignment_end <= first_stmt_end or assignment_end >= end_idx) return false;
    if (tokens[first_stmt_end].kind != .ident or
        !std.mem.eql(u8, tokens[first_stmt_end].lexeme, list_name) or
        first_stmt_end + 4 >= assignment_end or !tok_eq(tokens[first_stmt_end + 1], "=") or
        !tok_eq(tokens[first_stmt_end + 2], "@") or !tok_eq(tokens[first_stmt_end + 3], "set") or
        !tok_eq(tokens[first_stmt_end + 4], "(")) return false;

    const close_idx = find_matching_in_range(tokens, first_stmt_end + 4, "(", ")", assignment_end) catch return false;
    if (close_idx + 1 != assignment_end) return false;
    const receiver_start = first_stmt_end + 5;
    const receiver_end = find_arg_end(tokens, receiver_start, close_idx);
    if (receiver_end >= close_idx or !tok_eq(tokens[receiver_end], ",") or
        receiver_end != receiver_start + 1 or tokens[receiver_start].kind != .ident or
        !std.mem.eql(u8, tokens[receiver_start].lexeme, list_name)) return false;
    const index_start = receiver_end + 1;
    const index_end = find_arg_end(tokens, index_start, close_idx);
    if (index_end >= close_idx or !tok_eq(tokens[index_end], ",") or
        index_end != index_start + 1 or tokens[index_start].kind != .number) return false;
    const value_start = index_end + 1;
    const value_end = find_arg_end(tokens, value_start, close_idx);
    if (value_end != close_idx or value_end != value_start + 1 or tok_eq(tokens[value_start], "...")) return false;
    return tok_eq(tokens[assignment_end], "return") and find_stmt_end(tokens, assignment_end, end_idx) == end_idx;
}

fn tokens_have_field_reflection(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, index| {
        if (tok_eq(token, "fields") and index + 1 < tokens.len and tok_eq(tokens[index + 1], "(")) return true;
    }
    return false;
}

fn tokens_have_gc_sync_field_reflection(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    var found = false;
    while (i + 7 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "loop") or tokens[i + 1].kind != .ident or !tok_eq(tokens[i + 2], "=") or
            !tok_eq(tokens[i + 3], "fields") or !tok_eq(tokens[i + 4], "(") or
            tokens[i + 5].kind != .ident or !tok_eq(tokens[i + 6], ")")) continue;
        const open_brace = i + 7;
        if (!tok_eq(tokens[open_brace], "{") or !is_declared_type_name(tokens[i + 5].lexeme)) continue;
        const close_brace = find_matching(tokens, open_brace, "{", "}") catch continue;
        const has_defer = tokens_have_gc_sync_field_reflection_defer_token(tokens, i);
        var stmt = open_brace + 1;
        var saw_get = false;
        while (stmt < close_brace) {
            const stmt_end = find_stmt_end(tokens, stmt, close_brace);
            if (stmt_end <= stmt or !tok_eq(tokens[stmt], "if")) break;
            const if_open = find_top_level_block_open(tokens, stmt + 1, stmt_end) orelse break;
            const if_close = find_matching(tokens, if_open, "{", "}") catch break;
            if (if_close + 1 != stmt_end or stmt + 12 != if_open) break;
            if (if_close < if_open + 9) break;
            if (!tok_eq(tokens[stmt + 1], "@") or !tok_eq(tokens[stmt + 2], "eq") or !tok_eq(tokens[stmt + 3], "(") or
                !tok_eq(tokens[stmt + 4], "@") or !tok_eq(tokens[stmt + 5], "field_name") or !tok_eq(tokens[stmt + 6], "(") or
                tokens[stmt + 7].kind != .ident or !std.mem.eql(u8, tokens[stmt + 7].lexeme, tokens[i + 1].lexeme) or
                !tok_eq(tokens[stmt + 8], ")") or !tok_eq(tokens[stmt + 9], ",") or tokens[stmt + 10].kind != .string or
                !tok_eq(tokens[stmt + 11], ")")) break;
            const direct_body = if_close == if_open + 9 and tok_eq(tokens[if_open + 1], "return") and
                tok_eq(tokens[if_open + 2], "@") and tok_eq(tokens[if_open + 3], "field_get") and
                tok_eq(tokens[if_open + 4], "(") and tok_eq(tokens[if_open + 8], ")") and
                tokens[if_open + 5].kind == .ident and tok_eq(tokens[if_open + 6], ",") and
                tokens[if_open + 7].kind == .ident and
                std.mem.eql(u8, tokens[if_open + 7].lexeme, tokens[i + 1].lexeme);
            var live_source_body = false;
            if (!direct_body and if_open + 6 < if_close and tokens[if_open + 6].kind == .ident) {
                live_source_body = tokens_have_gc_sync_field_reflection_live_source_body(
                    tokens,
                    if_open + 1,
                    if_close,
                    tokens[if_open + 6].lexeme,
                    tokens[i + 1].lexeme,
                );
            }
            if (!direct_body and !live_source_body) break;
            const root_name = if (direct_body) tokens[if_open + 5].lexeme else tokens[if_open + 6].lexeme;
            if (!tokens_have_gc_sync_field_reflection_root(tokens, i, root_name, tokens[i + 5].lexeme)) break;
            if (has_defer and !tokens_have_gc_sync_field_reflection_bounded_defer(tokens, i)) break;
            saw_get = true;
            stmt = stmt_end;
        }
        if (saw_get and stmt == close_brace) {
            found = true;
            break;
        }
        i = close_brace;
    }
    return found;
}

fn tokens_have_gc_sync_field_reflection_live_source_body(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    root_name: []const u8,
    field_loop_name: []const u8,
) bool {
    // Keep this admission to the one source-live shape covered by 198: read
    // the reflected field, read one scalar sibling, guard on that scalar, then
    // return the reflected value.
    const field_get_end = find_stmt_end(tokens, start_idx, end_idx);
    if (field_get_end != start_idx + 9 or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "=") or !tok_eq(tokens[start_idx + 2], "@") or
        !tok_eq(tokens[start_idx + 3], "field_get") or !tok_eq(tokens[start_idx + 4], "(") or
        tokens[start_idx + 5].kind != .ident or !std.mem.eql(u8, tokens[start_idx + 5].lexeme, root_name) or
        !tok_eq(tokens[start_idx + 6], ",") or tokens[start_idx + 7].kind != .ident or
        !std.mem.eql(u8, tokens[start_idx + 7].lexeme, field_loop_name) or !tok_eq(tokens[start_idx + 8], ")")) return false;

    const scalar_start = field_get_end;
    const scalar_end = find_stmt_end(tokens, scalar_start, end_idx);
    if (scalar_end != scalar_start + 10 or tokens[scalar_start].kind != .ident or
        tokens[scalar_start + 1].kind != .ident or !tok_eq(tokens[scalar_start + 2], "=") or
        !tok_eq(tokens[scalar_start + 3], "@") or !tok_eq(tokens[scalar_start + 4], "get") or
        !tok_eq(tokens[scalar_start + 5], "(") or tokens[scalar_start + 6].kind != .ident or
        !std.mem.eql(u8, tokens[scalar_start + 6].lexeme, root_name) or !tok_eq(tokens[scalar_start + 7], ",") or
        tokens[scalar_start + 8].kind != .ident or tokens[scalar_start + 8].lexeme.len < 2 or
        tokens[scalar_start + 8].lexeme[0] != '.' or !tok_eq(tokens[scalar_start + 9], ")")) return false;

    const guard_start = scalar_end;
    const guard_end = find_stmt_end(tokens, guard_start, end_idx);
    if (guard_end != guard_start + 10 or !tok_eq(tokens[guard_start], "if") or
        !tok_eq(tokens[guard_start + 1], "@") or !tok_eq(tokens[guard_start + 2], "eq") or
        !tok_eq(tokens[guard_start + 3], "(") or tokens[guard_start + 4].kind != .ident or
        !std.mem.eql(u8, tokens[guard_start + 4].lexeme, tokens[scalar_start].lexeme) or
        !tok_eq(tokens[guard_start + 5], ",") or tokens[guard_start + 6].kind != .number or
        !tok_eq(tokens[guard_start + 7], ")") or !tok_eq(tokens[guard_start + 8], "return") or
        tokens[guard_start + 9].kind != .string) return false;

    const return_start = guard_end;
    return find_stmt_end(tokens, return_start, end_idx) == end_idx and return_start + 2 == end_idx and
        tok_eq(tokens[return_start], "return") and tokens[return_start + 1].kind == .ident and
        std.mem.eql(u8, tokens[return_start + 1].lexeme, tokens[start_idx].lexeme);
}

fn tokens_have_gc_sync_field_reflection_defer_token(tokens: []const lexer.Token, loop_idx: usize) bool {
    var i: usize = 0;
    while (i + 1 < loop_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "(") or !is_top_level_decl_head(tokens, i)) continue;
        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        if (close_params >= loop_idx) continue;
        const body_open = find_top_level_block_open(tokens, close_params + 1, loop_idx) orelse continue;
        if (body_open >= loop_idx) continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (loop_idx >= body_close) continue;
        for (tokens[body_open + 1 .. loop_idx]) |token| {
            if (tok_eq(token, "defer")) return true;
        }
        i = body_close;
    }
    return false;
}

fn tokens_have_gc_sync_field_reflection_bounded_defer(tokens: []const lexer.Token, loop_idx: usize) bool {
    var i: usize = 0;
    while (i + 1 < loop_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "(") or !is_top_level_decl_head(tokens, i)) continue;
        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        if (close_params >= loop_idx) continue;
        const body_open = find_top_level_block_open(tokens, close_params + 1, loop_idx) orelse continue;
        if (body_open >= loop_idx) continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (loop_idx >= body_close) continue;
        var defer_count: usize = 0;
        var stmt = body_open + 1;
        while (stmt < loop_idx) {
            const stmt_end = find_stmt_end(tokens, stmt, loop_idx);
            if (stmt_end <= stmt) break;
            if (tok_eq(tokens[stmt], "defer")) {
                if (stmt + 3 >= stmt_end or tokens[stmt + 1].kind != .ident or !tok_eq(tokens[stmt + 2], "(")) break;
                const close_idx = find_matching_in_range(tokens, stmt + 2, "(", ")", stmt_end) catch break;
                if (close_idx != stmt + 3 or close_idx + 1 != stmt_end) break;
                defer_count += 1;
            }
            stmt = stmt_end;
        }
        if (stmt == loop_idx and defer_count == 1) return true;
        i = body_close;
    }
    return false;
}

fn tokens_have_gc_sync_field_reflection_root(tokens: []const lexer.Token, loop_idx: usize, root_name: []const u8, root_ty: []const u8) bool {
    if (tokens_have_gc_sync_field_reflection_root_param(tokens, loop_idx, root_name, root_ty)) return true;

    // A fresh local struct constructor has the same stable GC root as a
    // parameter for this bounded reflection shape. Keep the admission tied to
    // a direct constructor before the reflection loop; arbitrary producers and
    // later reassignments remain on the ARC route.
    var i: usize = 0;
    while (i + 1 < loop_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "(") or !is_top_level_decl_head(tokens, i)) continue;
        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        if (close_params >= loop_idx) continue;
        const body_open = find_top_level_block_open(tokens, close_params + 1, loop_idx) orelse continue;
        if (body_open >= loop_idx) continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (loop_idx >= body_close) continue;

        var stmt = body_open + 1;
        while (stmt < loop_idx) {
            const stmt_end = find_stmt_end(tokens, stmt, loop_idx);
            if (stmt_end <= stmt) break;
            if (stmt + 5 < stmt_end and tokens[stmt].kind == .ident and
                std.mem.eql(u8, tokens[stmt].lexeme, root_name) and
                tokens[stmt + 1].kind == .ident and std.mem.eql(u8, tokens[stmt + 1].lexeme, root_ty) and
                tok_eq(tokens[stmt + 2], "=") and tokens[stmt + 3].kind == .ident and
                std.mem.eql(u8, tokens[stmt + 3].lexeme, root_ty) and tok_eq(tokens[stmt + 4], "{"))
            {
                const ctor_close = find_matching_in_range(tokens, stmt + 4, "{", "}", stmt_end) catch break;
                if (ctor_close + 1 == stmt_end) return true;
            }
            stmt = stmt_end;
        }
        i = body_close;
    }
    return false;
}

fn tokens_have_gc_sync_field_reflection_root_param(tokens: []const lexer.Token, loop_idx: usize, root_name: []const u8, root_ty: []const u8) bool {
    var i: usize = 0;
    while (i + 1 < loop_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "(") or !is_top_level_decl_head(tokens, i)) continue;
        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        if (close_params >= loop_idx) continue;
        const body_open = find_top_level_block_open(tokens, close_params + 1, loop_idx) orelse continue;
        if (body_open >= loop_idx) continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (loop_idx >= body_close) continue;
        var param = i + 2;
        while (param < close_params) {
            const param_end = find_arg_end(tokens, param, close_params);
            if (param_end == param + 2 and tokens[param].kind == .ident and tokens[param + 1].kind == .ident and
                std.mem.eql(u8, tokens[param].lexeme, root_name) and std.mem.eql(u8, tokens[param + 1].lexeme, root_ty)) return true;
            param = param_end;
            if (param < close_params and tok_eq(tokens[param], ",")) param += 1;
        }
    }
    return false;
}

fn gc_sync_scalar_union_segment_is_supported(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 != end_idx or tokens[start_idx].kind != .ident) return false;
    const name = tokens[start_idx].lexeme;
    if (std.mem.eql(u8, name, "nil") or type_util.is_core_wasm_scalar(name) or
        codegen_collect_util.is_error_like_type(tokens, name)) return true;
    const range = find_top_level_struct_range(tokens, name) orelse return false;
    var i = range.open_idx + 1;
    var fields: usize = 0;
    while (i < range.close_idx) {
        if (i + 1 >= range.close_idx or tokens[i].kind != .ident or tokens[i + 1].kind != .ident or
            !type_util.is_core_wasm_scalar(tokens[i + 1].lexeme)) return false;
        fields += 1;
        i += 2;
    }
    return fields != 0;
}

fn gc_sync_header_has_scalar_union_result(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var arrow_idx: ?usize = null;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "->")) {
            arrow_idx = i;
            break;
        }
        if (tok_eq(tokens[i], "-") and i + 1 < end_idx and tok_eq(tokens[i + 1], ">")) {
            arrow_idx = i;
            break;
        }
    }
    const arrow = arrow_idx orelse return false;
    const result_start = arrow + if (tok_eq(tokens[arrow], "->")) @as(usize, 1) else @as(usize, 2);
    if (result_start >= end_idx or find_top_level_token(tokens, result_start, end_idx, "|") == null) return false;
    var branch_start = result_start;
    var branch_count: usize = 0;
    var saw_scalar_struct = false;
    var saw_error = false;
    while (branch_start < end_idx) {
        const branch_end = find_top_level_token(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (!gc_sync_scalar_union_segment_is_supported(tokens, branch_start, branch_end)) return false;
        if (branch_end == branch_start + 1 and tokens[branch_start].kind == .ident) {
            const name = tokens[branch_start].lexeme;
            if (codegen_collect_util.is_error_like_type(tokens, name)) {
                saw_error = true;
            } else if (find_top_level_struct_range(tokens, name) != null) {
                saw_scalar_struct = true;
            }
        }
        branch_count += 1;
        if (branch_end == end_idx) break;
        branch_start = branch_end + 1;
    }
    return branch_count >= 2 and saw_scalar_struct and saw_error;
}

fn gc_sync_header_has_managed_union_result(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var arrow_idx: ?usize = null;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "->")) {
            arrow_idx = i;
            break;
        }
        if (tok_eq(tokens[i], "-") and i + 1 < end_idx and tok_eq(tokens[i + 1], ">")) {
            arrow_idx = i;
            break;
        }
    }
    const arrow = arrow_idx orelse return false;
    const result_start = arrow + if (tok_eq(tokens[arrow], "->")) @as(usize, 1) else @as(usize, 2);
    if (result_start >= end_idx or find_top_level_token(tokens, result_start, end_idx, "|") == null) return false;
    var branch_start = result_start;
    var branch_count: usize = 0;
    var saw_nil = false;
    var saw_bytes = false;
    while (branch_start < end_idx) {
        const branch_end = find_top_level_token(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start + 1 and tok_eq(tokens[branch_start], "nil")) {
            saw_nil = true;
        } else if (branch_end == branch_start + 3 and tok_eq(tokens[branch_start], "[") and
            tok_eq(tokens[branch_start + 1], "u8") and tok_eq(tokens[branch_start + 2], "]"))
        {
            saw_bytes = true;
        } else if (!gc_sync_scalar_union_segment_is_supported(tokens, branch_start, branch_end)) {
            return false;
        }
        branch_count += 1;
        if (branch_end == end_idx) break;
        branch_start = branch_end + 1;
    }
    return branch_count >= 2 and saw_nil and saw_bytes;
}

fn body_has_gc_sync_managed_union_unsupported_shape(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "@") and tok_eq(tokens[i + 1], "is")) return true;
    }
    return false;
}

fn gc_sync_header_has_unmanaged_struct_result(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var after_arrow = false;
    var angle_depth: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const token = tokens[i];
        if (tok_eq(token, "->") or (tok_eq(token, "-") and i + 1 < end_idx and tok_eq(tokens[i + 1], ">"))) {
            after_arrow = true;
            if (tok_eq(token, "-")) i += 1;
            continue;
        }
        if (!after_arrow) continue;
        if (tok_eq(token, "<")) {
            angle_depth += 1;
            continue;
        }
        if (tok_eq(token, ">")) {
            if (angle_depth != 0) angle_depth -= 1;
            continue;
        }
        if (angle_depth == 0 and token.kind == .ident and is_declared_type_name(token.lexeme)) {
            // Named payload/value enums are already represented by the GC
            // union path. Only ordinary struct results need this fallback
            // check; treating every declared type as a struct would reject
            // the bounded payload-union admission.
            if (find_top_level_struct_range(tokens, token.lexeme) != null and
                !struct_name_is_managed(tokens, token.lexeme, 0)) return true;
        }
    }
    return false;
}

fn tokens_have_multiple_managed_gets_in_call(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "(")) continue;
        const close_idx = find_matching(tokens, i, "(", ")") catch continue;
        var get_count: usize = 0;
        var j = i + 1;
        while (j + 1 < close_idx) : (j += 1) {
            if (tok_eq(tokens[j], "@") and tok_eq(tokens[j + 1], "get")) get_count += 1;
            if (get_count >= 2) return true;
        }
        i = close_idx;
    }
    return false;
}

fn body_has_gc_sync_inferred_text_binding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "=") or tokens[i + 2].kind != .string) continue;
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_end == i + 3) return true;
    }
    return false;
}

fn tokens_have_gc_sync_test_candidate(tokens: []const lexer.Token) bool {
    if (tokens_have_field_reflection(tokens)) return false;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "test")) continue;
        const body_open = find_top_level_block_open(tokens, i + 1, tokens.len) orelse continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (body_has_gc_sync_inferred_text_binding(tokens, body_open + 1, body_close)) return true;
        for (tokens[body_open + 1 .. body_close]) |token| {
            if (token.kind == .ident and std.mem.eql(u8, token.lexeme, "text")) return true;
            if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "[")) return true;
            if (token.kind == .ident and is_declared_type_name(token.lexeme) and
                struct_name_is_managed(tokens, token.lexeme, 0)) return true;
        }
        i = body_close;
    }
    return false;
}

fn gc_sync_header_has_bounded_multi_result(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var arrow_idx: ?usize = null;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "->")) {
            arrow_idx = i;
            break;
        }
        if (tok_eq(tokens[i], "-") and i + 1 < end_idx and tok_eq(tokens[i + 1], ">")) {
            arrow_idx = i;
            break;
        }
    }
    const arrow = arrow_idx orelse return false;
    const result_start = arrow + if (tok_eq(tokens[arrow], "->")) @as(usize, 1) else @as(usize, 2);
    if (result_start >= end_idx) return false;

    var segment_start = result_start;
    var angle_depth: usize = 0;
    var saw_separator = false;
    i = result_start;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "<")) {
            angle_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (angle_depth == 0) return false;
            angle_depth -= 1;
            continue;
        }
        if (angle_depth == 0 and tok_eq(tokens[i], ",")) {
            if (!gc_sync_result_segment_is_bounded(tokens, segment_start, i)) return false;
            saw_separator = true;
            segment_start = i + 1;
        }
    }
    if (!saw_separator or angle_depth != 0 or !gc_sync_result_segment_is_bounded(tokens, segment_start, end_idx)) return false;
    return true;
}

fn gc_sync_header_has_single_bounded_managed_param(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "(")) return false;
    const close_params = find_matching_in_range(tokens, start_idx, "(", ")", end_idx) catch return false;
    if (close_params != start_idx + 5 or tokens[start_idx + 1].kind != .ident or
        !tok_eq(tokens[start_idx + 2], "[") or tokens[start_idx + 3].kind != .ident or
        !std.mem.eql(u8, tokens[start_idx + 3].lexeme, "u8") or !tok_eq(tokens[start_idx + 4], "]")) return false;
    if (close_params + 1 >= end_idx) return false;
    return tok_eq(tokens[close_params + 1], "->") or
        (tok_eq(tokens[close_params + 1], "-") and close_params + 2 < end_idx and tok_eq(tokens[close_params + 2], ">"));
}

fn gc_sync_header_has_inline_scalar_struct_result(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var arrow_idx: ?usize = null;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "->")) {
            arrow_idx = i;
            break;
        }
        if (tok_eq(tokens[i], "-") and i + 1 < end_idx and tok_eq(tokens[i + 1], ">")) {
            arrow_idx = i;
            break;
        }
    }
    const arrow = arrow_idx orelse return false;
    const result_start = arrow + if (tok_eq(tokens[arrow], "->")) @as(usize, 1) else @as(usize, 2);
    if (result_start + 1 != end_idx or tokens[result_start].kind != .ident) return false;
    const result_name = tokens[result_start].lexeme;
    const range = find_top_level_struct_range(tokens, result_name) orelse return false;
    var field_count: usize = 0;
    i = range.open_idx + 1;
    while (i < range.close_idx) {
        if (i + 1 >= range.close_idx or tokens[i].kind != .ident or tokens[i + 1].kind != .ident or
            !type_util.is_core_wasm_scalar(tokens[i + 1].lexeme)) return false;
        field_count += 1;
        i += 2;
    }
    return field_count != 0;
}

fn body_has_gc_sync_inline_scalar_struct_result(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var saw_struct_literal = false;
    var saw_struct_binding = false;
    var saw_return = false;
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_end <= i) return false;
        if (tok_eq(tokens[i], "if") or tok_eq(tokens[i], "loop") or tok_eq(tokens[i], "defer")) return false;
        if (tok_eq(tokens[i], "return")) {
            if (stmt_end <= i + 1 or tokens[i + 1].kind != .ident or find_stmt_end(tokens, i, end_idx) != end_idx) return false;
            saw_return = true;
        }
        var j = i;
        while (j + 1 < stmt_end) : (j += 1) {
            if (tokens[j].kind == .ident and tok_eq(tokens[j + 1], "{")) saw_struct_literal = true;
            if (j + 2 < stmt_end and tokens[j].kind == .ident and tokens[j + 1].kind == .ident and
                tok_eq(tokens[j + 2], "=") and find_top_level_struct_range(tokens, tokens[j + 1].lexeme) != null)
            {
                saw_struct_binding = true;
            }
        }
        i = stmt_end;
    }
    return saw_struct_literal and saw_struct_binding and saw_return;
}

fn gc_sync_header_has_managed_struct_multi_result(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var arrow_idx: ?usize = null;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "->")) {
            arrow_idx = i;
            break;
        }
        if (tok_eq(tokens[i], "-") and i + 1 < end_idx and tok_eq(tokens[i + 1], ">")) {
            arrow_idx = i;
            break;
        }
    }
    const arrow = arrow_idx orelse return false;
    const result_start = arrow + if (tok_eq(tokens[arrow], "->")) @as(usize, 1) else @as(usize, 2);
    var segment_start = result_start;
    var angle_depth: usize = 0;
    var saw_separator = false;
    i = result_start;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "<")) {
            angle_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (angle_depth == 0) return false;
            angle_depth -= 1;
            continue;
        }
        if (angle_depth == 0 and tok_eq(tokens[i], ",")) {
            if (segment_start + 1 != i or tokens[segment_start].kind != .ident or
                !is_declared_type_name(tokens[segment_start].lexeme) or
                !struct_name_is_managed(tokens, tokens[segment_start].lexeme, 0)) return false;
            saw_separator = true;
            segment_start = i + 1;
        }
    }
    if (!saw_separator or angle_depth != 0 or segment_start + 1 != end_idx or
        tokens[segment_start].kind != .ident or !is_declared_type_name(tokens[segment_start].lexeme) or
        !struct_name_is_managed(tokens, tokens[segment_start].lexeme, 0)) return false;
    return true;
}

fn gc_sync_result_segment_is_bounded(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        return type_util.is_core_wasm_scalar(tokens[start_idx].lexeme);
    }
    return end_idx == start_idx + 3 and tok_eq(tokens[start_idx], "[") and
        tokens[start_idx + 1].kind == .ident and std.mem.eql(u8, tokens[start_idx + 1].lexeme, "u8") and
        tok_eq(tokens[start_idx + 2], "]");
}

fn gc_sync_header_has_unsupported_shape(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var after_arrow = false;
    var angle_depth: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const token = tokens[i];
        if (tok_eq(token, "->") or (tok_eq(token, "-") and i + 1 < end_idx and tok_eq(tokens[i + 1], ">"))) {
            after_arrow = true;
            if (tok_eq(token, "-")) i += 1;
            continue;
        }
        if (after_arrow and tok_eq(token, "<")) {
            angle_depth += 1;
            continue;
        }
        if (after_arrow and tok_eq(token, ">")) {
            if (angle_depth != 0) angle_depth -= 1;
            continue;
        }
        // Union parameters are outside the current parsed GC contract. A
        // top-level result union is admitted separately by the scalar-union
        // header probe and remains fail-closed in the typed emitter.
        if (!after_arrow and (tok_eq(token, "|") or tok_eq(token, "Result"))) return true;
        if (after_arrow and (tok_eq(token, "Result") or tok_eq(token, "Future") or tok_eq(token, "Stream"))) return true;
        if (!after_arrow) continue;
        // A comma at the top level means multiple results. Commas nested in a
        // generic Tuple type are part of one managed result and are admitted
        // when the parsed GC emitter has an exact lowering for that shape.
        if ((tok_eq(token, ",") and angle_depth == 0 and
            !gc_sync_header_has_bounded_multi_result(tokens, start_idx, end_idx) and
            !gc_sync_header_has_managed_struct_multi_result(tokens, start_idx, end_idx)) or
            (tok_eq(token, "|") and !gc_sync_header_has_scalar_union_result(tokens, start_idx, end_idx) and
                !gc_sync_header_has_managed_union_result(tokens, start_idx, end_idx)) or
            tok_eq(token, "Result") or tok_eq(token, "Future") or
            tok_eq(token, "Stream")) return true;
    }
    return false;
}

const StructTokenRange = struct {
    open_idx: usize,
    close_idx: usize,
};

fn is_top_level_struct_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len or tokens[idx].kind != .ident) return false;
    if (!is_declared_type_name(tokens[idx].lexeme) or !is_top_level_decl_head(tokens, idx)) return false;
    if (idx > 0 and tok_eq(tokens[idx - 1], "->")) return false;
    return tok_eq(tokens[idx + 1], "{");
}

fn tokens_have_managed_struct_declaration(tokens: []const lexer.Token) bool {
    var depth: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (depth == 0 and is_top_level_struct_decl_start(tokens, i)) {
            const close_idx = find_matching(tokens, i + 1, "{", "}") catch {
                i += 1;
                continue;
            };
            for (tokens[i + 2 .. close_idx]) |token| {
                if (token.kind == .ident and std.mem.eql(u8, token.lexeme, "text")) return true;
                if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "[")) return true;
            }
            i = close_idx;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth += 1;
        } else if (tok_eq(tokens[i], "}") and depth != 0) {
            depth -= 1;
        }
    }
    return false;
}

fn find_top_level_struct_range(tokens: []const lexer.Token, name: []const u8) ?StructTokenRange {
    var depth: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (depth == 0 and is_top_level_struct_decl_start(tokens, i) and
            std.mem.eql(u8, tokens[i].lexeme, name))
        {
            const close_idx = find_matching(tokens, i + 1, "{", "}") catch return null;
            return .{ .open_idx = i + 1, .close_idx = close_idx };
        }
        if (tok_eq(tokens[i], "{")) {
            depth += 1;
        } else if (tok_eq(tokens[i], "}") and depth != 0) {
            depth -= 1;
        }
    }
    return null;
}

fn struct_name_is_managed(tokens: []const lexer.Token, name: []const u8, depth: usize) bool {
    if (depth > tokens.len or !is_declared_type_name(name)) return false;
    const range = find_top_level_struct_range(tokens, name) orelse return false;
    for (tokens[range.open_idx + 1 .. range.close_idx]) |token| {
        if (token.kind == .ident and std.mem.eql(u8, token.lexeme, "text")) return true;
        if (token.kind == .symbol and std.mem.eql(u8, token.lexeme, "[")) return true;
    }
    var i = range.open_idx + 1;
    while (i + 1 < range.close_idx) : (i += 1) {
        if (tokens[i].kind != .ident or tokens[i + 1].kind != .ident or
            !is_declared_type_name(tokens[i + 1].lexeme)) continue;
        if (struct_name_is_managed(tokens, tokens[i + 1].lexeme, depth + 1)) return true;
    }
    return false;
}

fn tokens_have_host_or_wit_binding(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, index| {
        if (!tok_eq(token, "@") or index + 1 >= tokens.len or tokens[index + 1].kind != .ident) continue;
        const intrinsic = tokens[index + 1].lexeme;
        if (std.mem.eql(u8, intrinsic, "host") or
            std.mem.startsWith(u8, intrinsic, "host_") or
            std.mem.startsWith(u8, intrinsic, "wasi_")) return true;
    }
    return false;
}

fn graph_has_gc_sync_candidate(graph: *const imports.ModuleGraph) bool {
    for (graph.modules) |module| {
        if (tokens_have_gc_sync_candidate(module.tokens)) return true;
    }
    return false;
}

fn graph_has_host_or_wit_binding(graph: *const imports.ModuleGraph) bool {
    for (graph.modules) |module| {
        if (tokens_have_host_or_wit_binding(module.tokens)) return true;
    }
    return false;
}

fn is_gc_sync_capability_error(err: anyerror) bool {
    return switch (err) {
        error.GcSyncArityMismatch,
        error.GcSyncTypeMismatch,
        error.MissingGcSyncReturn,
        error.NoMatchingCall,
        error.ResourceInManagedAggregate,
        error.UnsupportedLowering,
        error.UnexpectedGcSyncReturn,
        error.UnknownGcSyncLocal,
        error.UnknownType,
        error.UnsupportedGcAggregate,
        error.UnsupportedGcSyncAggregate,
        error.UnsupportedGcSyncAsync,
        error.UnsupportedGcSyncCall,
        error.UnsupportedGcSyncCallback,
        error.UnsupportedGcSyncControl,
        error.UnsupportedGcSyncExpression,
        error.UnsupportedGcSyncGenericResource,
        error.UnsupportedGcSyncGenericUnion,
        error.UnsupportedGcSyncGenericUnresolved,
        error.UnsupportedGcSyncModuleGraph,
        error.UnsupportedGcSyncOverload,
        error.UnsupportedGcSyncProducer,
        error.UnsupportedGcSyncProgram,
        error.UnsupportedGcSyncResult,
        error.UnsupportedGcSyncStatement,
        error.UnsupportedGcSyncTupleStorage,
        error.UnsupportedGcSyncType,
        error.UnsupportedGcSyncUnionArms,
        error.UnsupportedGcSyncUnionConstructor,
        error.UnsupportedGcSyncUnionPayload,
        => true,
        else => false,
    };
}

fn validate_gc_sync_output(wat: []const u8) !void {
    if (std.mem.indexOf(u8, wat, "__arc_") != null) {
        return error.GcSyncOutputContainsArc;
    }
}

fn emit_checked_gc_sync(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    const wat = try codegen_gc_sync.emit_gc_wat_for_supported_program(allocator, program, tokens, module_graph);
    validate_gc_sync_output(wat) catch |err| {
        allocator.free(wat);
        return err;
    };
    return wat;
}

fn try_emit_default_gc_sync(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) !?[]u8 {
    // Imported modules and host/WIT declarations remain outside the parsed
    // GC admission boundary until their ABI/resource rows close. Only the
    // entry module can select this synchronous route for now.
    const candidate = tokens_have_gc_sync_candidate(tokens);
    if (!candidate) return null;
    if (tokens_have_host_or_wit_binding(tokens)) return null;
    if (module_graph) |graph| if (graph_has_host_or_wit_binding(graph)) return null;

    const wat = emit_checked_gc_sync(allocator, program, tokens, module_graph) catch |err| {
        // A managed candidate must never silently re-enter the ARC emitter.
        // Unsupported shapes remain explicit capability errors until their GC
        // lowering is admitted by the migration ledger.
        if (is_gc_sync_capability_error(err)) return err;
        return err;
    };
    return wat;
}

pub fn emit_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
    return emit_wat_with_options(allocator, program, tokens, module_graph, .{});
}

test "aggregate await tokens require async lowering" {
    const tokens = try lexer.tokenize(std.testing.allocator, "start() { await_all(left, right) }");
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(tokens_require_async_lowering(tokens));
}

test "GC candidate scan skips scalar-only control flow" {
    const source =
        \\sum_tail(n i32, acc i32) -> i32 {
        \\    if @eq(n, 0) return acc
        \\    next_n i32 = @sub(n, 1)
        \\    next_acc i32 = @add(acc, n)
        \\    return sum_tail(next_n, next_acc)
        \\}
        \\start() {
        \\    out i32 = sum_tail(5, 0)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits managed locals in a function body" {
    const source =
        \\start() {
        \\    value text = "hello"
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits an inferred body-only text binding" {
    const source =
        \\make() -> text {
        \\    value = "hello"
        \\    return value
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "compiled-test candidate scan admits an inferred text binding" {
    const source =
        \\test "inferred text" {
        \\    value = "hello"
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_test_candidate(tokens));
}

test "GC candidate scan leaves recv loops on the legacy route" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\take(box Box) -> i32 {
        \\    return @len(@get(box, .value))
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    one Box = Box{value = bytes}
        \\    boxes [Box] = .{one}
        \\    loop item, count = recv(boxes) {
        \\        _ = take(item)
        \\        if @eq(count, 0) break
        \\    }
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan leaves unsupported body text intrinsic on legacy route" {
    const source =
        \\start() {
        \\    value text = "hello"
        \\    n = @len(value)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a body-only byte-list literal" {
    const source =
        \\start() {
        \\    values [u8] = .{1, 2}
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a body-only byte-list fallthrough" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a bounded byte-list literal overwrite" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    data = "def"
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a bounded byte-list guard return" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    ok bool = true
        \\    if ok return
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a bounded byte-list block return" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    if @eq(@len(data), 3) {
        \\        return
        \\    }
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits the on-disk bounded byte-list block return" {
    const source = "start() {\n    data [u8] = \"abc\"\n    if @eq(@len(data), 3) {\n        return\n    }\n    return\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits the on-disk bounded byte-list if-else return" {
    const source = "start() {\n    data [u8] = \"abc\"\n    if @eq(@len(data), 3) {\n        return\n    } else {\n        return\n    }\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits the on-disk bounded byte-list else-if return" {
    const source = "start() {\n    data [u8] = \"abc\"\n    if @eq(@len(data), 1) {\n        return\n    } else if @eq(@len(data), 3) {\n        return\n    } else {\n        return\n    }\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded byte-list block return through GC" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    if @eq(@len(data), 3) {
        \\        return
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a bounded byte-list if-else return through GC" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    if @eq(@len(data), 3) {
        \\        return
        \\    } else {
        \\        return
        \\    }
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; if-else-block") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root branch_join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a bounded byte-list else-if return through GC" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    if @eq(@len(data), 1) {
        \\        return
        \\    } else if @eq(@len(data), 3) {
        \\        return
        \\    } else {
        \\        return
        \\    }
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root branch_join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded byte-list branch-local return" {
    const source = "start() {\n    if @eq(1, 1) {\n        data [u8] = \"abc\"\n        return\n    }\n    return\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded byte-list branch-local return through GC" {
    const source =
        \\start() {
        \\    if @eq(1, 1) {
        \\        data [u8] = "abc"
        \\        return
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root local_bind $data") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded byte-list branch-local fallthrough" {
    const source = "start() {\n    if @eq(1, 1) {\n        data [u8] = \"abc\"\n    }\n    return\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded byte-list branch-local fallthrough through GC" {
    const source =
        \\start() {
        \\    if @eq(1, 1) {
        \\        data [u8] = "abc"
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root local_bind $data") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded byte-list loop return" {
    const source = "start() {\n    data [u8] = \"abc\"\n    loop {\n        return\n    }\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded byte-list loop return through GC" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    loop {
        \\        return
        \\    }
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root local_bind $data") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root loop_join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded byte-list loop break" {
    const source = "start() {\n    loop {\n        data [u8] = \"abc\"\n        break\n    }\n    return\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a bounded cross-scope labeled byte-list break" {
    const source =
        "start() {\n" ++
        "#outer\n" ++
        "    loop {\n" ++
        "        outer [u8] = \"outer\"\n" ++
        "        loop {\n" ++
        "            inner [u8] = \"inner\"\n" ++
        "            break #outer\n" ++
        "        }\n" ++
        "    }\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded cross-scope labeled byte-list break through the outer GC block" {
    const source =
        "start() {\n" ++
        "#outer\n" ++
        "    loop {\n" ++
        "        outer [u8] = \"outer\"\n" ++
        "        loop {\n" ++
        "            inner [u8] = \"inner\"\n" ++
        "            break #outer\n" ++
        "        }\n" ++
        "    }\n" ++
        "    return\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "br $__gc_break_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "br $__gc_break_2") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded cross-scope labeled byte-list continue" {
    const source =
        "start() {\n" ++
        "#outer\n" ++
        "    loop {\n" ++
        "        outer [u8] = \"outer\"\n" ++
        "        loop {\n" ++
        "            inner [u8] = \"inner\"\n" ++
        "            continue #outer\n" ++
        "        }\n" ++
        "    }\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded cross-scope labeled continue through the outer GC loop" {
    const source =
        "start() {\n" ++
        "#outer\n" ++
        "    loop {\n" ++
        "        outer [u8] = \"outer\"\n" ++
        "        loop {\n" ++
        "            inner [u8] = \"inner\"\n" ++
        "            continue #outer\n" ++
        "        }\n" ++
        "    }\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "br $__gc_loop_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "br $__gc_loop_3") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded managed byte-list alias" {
    const source =
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    alias [u8] = data\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded managed byte-list alias through GC" {
    const source =
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    alias [u8] = data\n" ++
        "    return\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $alias") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded managed struct alias" {
    const source =
        "Box {\n" ++
        "    value [u8]\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    bytes [u8] = \"abc\"\n" ++
        "    box Box = Box{value = bytes}\n" ++
        "    alias Box = box\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded managed struct alias through GC" {
    const source =
        "Box {\n" ++
        "    value [u8]\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    bytes [u8] = \"abc\"\n" ++
        "    box Box = Box{value = bytes}\n" ++
        "    alias Box = box\n" ++
        "    return\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $alias") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded managed byte-list local overwrite" {
    const source =
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    next [u8] = \"def\"\n" ++
        "    data = next\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded managed byte-list local overwrite through GC" {
    const source =
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    next [u8] = \"def\"\n" ++
        "    data = next\n" ++
        "    return\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root overwrite $data") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $next") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded managed multi-result call assignment" {
    const source =
        "pair_take(x [u8]) -> [u8], i32 {\n" ++
        "    return x, 3\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    out [u8] = .{}\n" ++
        "    n i32 = 0\n" ++
        "    out, n = pair_take(data)\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded managed multi-result call assignment through GC" {
    const source =
        "pair_take(x [u8]) -> [u8], i32 {\n" ++
        "    return x, 3\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    out [u8] = .{}\n" ++
        "    n i32 = 0\n" ++
        "    out, n = pair_take(data)\n" ++
        "    return\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $pair_take") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan rejects bounded multi-result calls with extra managed parameters" {
    const source =
        "pair_take(first [u8], second [u8]) -> [u8], i32 {\n" ++
        "    return first, 3\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a managed argument with a pure scalar struct result" {
    const source =
        "Point {\n" ++
        "    x i32\n" ++
        "    y i32\n" ++
        "}\n\n" ++
        "size_point(x [u8]) -> Point {\n" ++
        "    n i32 = @len(x)\n" ++
        "    p Point = Point{x = n, y = n}\n" ++
        "    return p\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    p Point = size_point(data)\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a managed argument with a pure scalar struct result through GC" {
    const source =
        "Point {\n" ++
        "    x i32\n" ++
        "    y i32\n" ++
        "}\n\n" ++
        "size_point(x [u8]) -> Point {\n" ++
        "    n i32 = @len(x)\n" ++
        "    p Point = Point{x = n, y = n}\n" ++
        "    return p\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    data [u8] = \"abc\"\n" ++
        "    p Point = size_point(data)\n" ++
        "    return\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $size_point (param $x (ref null $do_bytes)) (result i32 i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $size_point") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $p.y") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $p.x") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded multi-result return with a synchronous defer" {
    const source =
        "nop() -> nil {\n" ++
        "    return nil\n" ++
        "}\n\n" ++
        "pair_take(x [u8]) -> [u8], i32 {\n" ++
        "    return x, 3\n" ++
        "}\n\n" ++
        "pass(data [u8]) -> [u8], i32 {\n" ++
        "    defer nop()\n" ++
        "    return pair_take(data)\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    out [u8] = .{}\n" ++
        "    n i32 = 0\n" ++
        "    out, n = pass(\"abc\")\n" ++
        "    return\n" ++
        "}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded multi-result return with a synchronous defer through GC" {
    const source =
        "nop() -> nil {\n" ++
        "    return nil\n" ++
        "}\n\n" ++
        "pair_take(x [u8]) -> [u8], i32 {\n" ++
        "    return x, 3\n" ++
        "}\n\n" ++
        "pass(data [u8]) -> [u8], i32 {\n" ++
        "    defer nop()\n" ++
        "    return pair_take(data)\n" ++
        "}\n\n" ++
        "start() {\n" ++
        "    out [u8] = .{}\n" ++
        "    n i32 = 0\n" ++
        "    out, n = pass(\"abc\")\n" ++
        "    return\n" ++
        "}\n";
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $pair_take") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $nop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a bounded byte-list loop break through GC" {
    const source =
        \\start() {
        \\    loop {
        \\        data [u8] = "abc"
        \\        break
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root local_bind $data") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded byte-list loop continue" {
    const source = "start() {\n    loop {\n        data [u8] = \"abc\"\n        continue\n    }\n}\n";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded byte-list loop continue through GC" {
    const source =
        \\start() {
        \\    loop {
        \\        data [u8] = "abc"
        \\        continue
        \\    }
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root local_bind $data") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a bounded scalar multi-result program" {
    const source =
        \\pair() -> i32, bool {
        \\    return 1, true
        \\}
        \\
        \\start() {
        \\    a i32 = 0
        \\    ok bool = false
        \\    a, ok = pair()
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded scalar multi-result program through GC" {
    const source =
        \\pair() -> i32, bool {
        \\    return 1, true
        \\}
        \\
        \\start() {
        \\    a i32 = 0
        \\    ok bool = false
        \\    a, ok = pair()
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $pair (result i32 i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a mixed multi-result with an unreturned managed local through GC" {
    const source =
        \\make_partial() -> [u8], i32 {
        \\    keep [u8] = "keep"
        \\    drop [u8] = "drop"
        \\    return keep, 7
        \\}
        \\
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $make_partial (result (ref null $do_bytes) i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers nested managed fallthrough through GC" {
    const source =
        \\start() {
        \\    if @eq(1, 1) {
        \\        outer [u8] = "outer"
        \\        if @eq(1, 1) {
        \\            inner [u8] = "inner"
        \\        }
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $outer (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $inner (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root branch_join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits scalar multi-result passthrough" {
    const source =
        \\pair() -> i32, bool {
        \\    return 1, true
        \\}
        \\wrap() -> i32, bool {
        \\    return pair()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a bounded byte-list guard return through GC" {
    const source =
        \\start() {
        \\    data [u8] = "abc"
        \\    ok bool = true
        \\    if ok return
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits a body-only scalar-list literal" {
    const source =
        \\start() {
        \\    values [u32] = .{1, 2}
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits inferred managed list storage" {
    const source =
        \\start() {
        \\    seed [u8] = .{1}
        \\    values = @put(seed, 2)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits inferred non-byte scalar list storage" {
    const source =
        \\start() {
        \\    seed [u32] = .{1}
        \\    values = @put(seed, 2)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan leaves inferred unadmitted scalar list storage on legacy route" {
    const source =
        \\start() {
        \\    seed [f64] = .{1}
        \\    values = @put(seed, 2)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan leaves inferred managed list storage with extra control flow on legacy route" {
    const source =
        \\start() {
        \\    seed [u8] = .{1}
        \\    values = @put(seed, 2)
        \\    if @eq(@len(values), 2) return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a body-only managed struct storage update" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    box Box = Box{value = bytes, tag = 1}
        \\    updated Box = @set(box, .tag, 7)
        \\    value [u8] = @get(updated, .value)
        \\    if @eq(@len(value), 3) return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a body-only managed struct field read" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    box Box = Box{value = bytes}
        \\    value [u8] = @get(box, .value)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan leaves deferred managed struct field reads on the legacy route" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\nop() -> nil {
        \\    return nil
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    box Box = Box{value = bytes}
        \\    defer op()
        \\    value [u8] = @get(box, .value)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan leaves repeated managed struct field reads on the legacy route" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    box Box = Box{value = bytes}
        \\    first [u8] = @get(box, .value)
        \\    second [u8] = @get(box, .value)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits body-only managed field replacement" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    next [u8] = "def"
        \\    box Box = Box{value = bytes}
        \\    box = @set(box, .value, next)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan leaves managed field producer calls on the legacy route" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\make() -> i32 {
        \\    return 1
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    box Box = Box{value = bytes}
        \\    box = @set(box, .value, make())
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits body-only managed struct alias assignment" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    next_text [u8] = "def"
        \\    box Box = Box{value = bytes}
        \\    next_box Box = Box{value = next_text}
        \\    box = next_box
        \\    value [u8] = @get(next_box, .value)
        \\    size usize = @len(value)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a body-only managed field getter producer" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    other Box = Box{value = bytes}
        \\    box Box = Box{value = bytes}
        \\    box = @set(box, .value, @get(other, .value))
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a body-only managed struct storage update through GC" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    box Box = Box{value = bytes, tag = 1}
        \\    updated Box = @set(box, .tag, 7)
        \\    value [u8] = @get(updated, .value)
        \\    if @eq(@len(value), 3) return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__storage_") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__struct_literal_tmp") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan leaves body-only multi-value scalar-list updates on legacy route" {
    const source =
        \\start() {
        \\    values [u32] = .{1}
        \\    values = @put(values, 2, 3)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan leaves body-only dynamic scalar-list sets on legacy route" {
    const source =
        \\start() {
        \\    values [u32] = .{1}
        \\    index usize = 0
        \\    values = @set(values, index, 2)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC struct scan ignores function return braces" {
    const source =
        \\sum_tail(n i32, acc i32) -> i32 {
        \\    return acc
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(find_top_level_struct_range(tokens, "i32") == null);
}

test "GC candidate scan admits nested managed structs" {
    const source =
        \\Outer {
        \\    inner Inner
        \\    tag i32
        \\}
        \\Inner {
        \\    value [u8]
        \\}
        \\identity(box Outer) -> Outer {
        \\    return box
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan rejects managed unions in parameter types" {
    const source =
        \\emit_text(value text | nil) -> text {
        \\    if @eq(value, nil) return "null"
        \\    return value
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan rejects an unsupported overload in the same program" {
    const source =
        \\emit(value text, depth usize) -> text {
        \\    return value
        \\}
        \\#T
        \\emit(value T | nil, depth usize) -> text {
        \\    if @eq(value, nil) return "null"
        \\    return emit(value, depth)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan rejects field reflection until the GC emitter supports it" {
    const source =
        \\#T
        \\field_count(value T) -> usize {
        \\    count usize = 0
        \\    loop field = fields(T) {
        \\        count = @add(count, 1)
        \\    }
        \\    return count
        \\}
        \\User {
        \\    id i32
        \\    name text
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a static field reflection getter" {
    const source =
        \\User {
        \\    name text
        \\}
        \\take_name(user User) -> text {
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a static field reflection getter from a fresh local" {
    const source =
        \\User {
        \\    name text
        \\}
        \\take_name() -> text {
        \\    user User = User{name = "amy"}
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a static field reflection getter with bounded defer" {
    const source =
        \\nop() -> nil {
        \\    return nil
        \\}
        \\User {
        \\    name text
        \\}
        \\take_name(user User) -> text {
        \\    defer nop()
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits fresh local field reflection with defer" {
    const source =
        \\nop() -> nil {
        \\    return nil
        \\}
        \\User {
        \\    name text
        \\}
        \\take_name() -> text {
        \\    user User = User{name = "amy"}
        \\    defer nop()
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan rejects fresh local field reflection with managed defer argument" {
    const source =
        \\consume(value text) -> nil {
        \\    return nil
        \\}
        \\User {
        \\    name text
        \\}
        \\take_name() -> text {
        \\    user User = User{name = "amy"}
        \\    defer consume(@get(user, .name))
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan admits a live-source field reflection getter" {
    const source =
        \\User {
        \\    name text
        \\    id i32
        \\}
        \\take_name(user User) -> text {
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            got = @field_get(user, field)
        \\            id i32 = @get(user, .id)
        \\            if @eq(id, 0) return ""
        \\            return got
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "default GC route emits a static field reflection getter" {
    const source =
        \\User {
        \\    name text
        \\}
        \\take_name(user User) -> text {
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {
        \\    user User = User{name = "amy"}
        \\    name text = take_name(user)
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $user $name") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default GC route emits a fresh local field reflection getter with defer" {
    const source =
        \\noop() -> nil {
        \\    return nil
        \\}
        \\User {
        \\    name text
        \\}
        \\take_name() -> text {
        \\    user User = User{name = "amy"}
        \\    defer noop()
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {
        \\    name text = take_name()
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "field-reflect-gc type=User") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $noop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $user $name") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC candidate scan admits bounded synchronous managed defer bodies" {
    const source =
        \\noop() -> nil {
        \\    return nil
        \\}
        \\finish(value text) -> text {
        \\    defer noop()
        \\    return value
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan rejects managed inputs with an unmanaged struct result" {
    const source =
        \\Point {
        \\    x i32
        \\    y i32
        \\}
        \\size_point(value [u8]) -> Point {
        \\    n i32 = @len(value)
        \\    return Point{x = n, y = n}
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "GC candidate scan rejects multiple managed field reads in one call" {
    const source =
        \\same(left [u8], right [u8]) -> bool {
        \\    return @eq(left, right)
        \\}
        \\Pair {
        \\    left [u8]
        \\    right [u8]
        \\}
        \\start() {
        \\    pair Pair = Pair{left = "a", right = "b"}
        \\    _ = same(@get(pair, .left), @get(pair, .right))
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(!tokens_have_gc_sync_candidate(tokens));
}

test "default pipeline lowers a synchronous managed defer through GC" {
    const source =
        \\noop() -> nil {
        \\    return nil
        \\}
        \\make(value [u8]) -> [u8] {
        \\    return value
        \\}
        \\pass(value [u8]) -> [u8] {
        \\    defer noop()
        \\    return make(value)
        \\}
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $noop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "compiled scalar tests keep the ARC route before GC admission" {
    const source =
        \\sum_tail(n i32, acc i32) -> i32 {
        \\    if @eq(n, 0) return acc
        \\    next_n i32 = @sub(n, 1)
        \\    next_acc i32 = @add(acc, n)
        \\    return sum_tail(next_n, next_acc)
        \\}
        \\test "compiled scalar tail" {
        \\    out i32 = sum_tail(5, 0)
        \\    if @eq(out, 15) return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_test_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-sync") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "loop $__tail_sum_tail") != null);
}

test "normal pipeline exposes a private synchronous GC route" {
    try std.testing.expect(@hasField(EmitOptions, "gc_sync"));
}

test "private synchronous GC route emits typed GC for a parsed managed update" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\update(box Box, value [u8]) -> Box {
        \\    return @set(box, .value, value)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_wat_with_options(std.testing.allocator, program, tokens, null, .{ .gc_sync = true });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline retains ARC for an unconverted scalar path before the G5c cutover" {
    const source =
        \\identity(value u32) -> u32 {
        \\    return value
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_wat_with_options(std.testing.allocator, program, tokens, null, .{});
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_text") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") != null);
}

test "default pipeline lowers an admitted synchronous managed identity through GC" {
    const source =
        \\identity(value text) -> text {
        \\    return value
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_wat_with_options(std.testing.allocator, program, tokens, null, .{});
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root local_bind") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a body-only managed local through GC" {
    const source =
        \\start() {
        \\    value text = "hello"
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root local_bind $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers an inferred body-only text binding through GC" {
    const source =
        \\make() -> text {
        \\    value = "hello"
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $value\n    ;; gc-root local_bind $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline distinguishes inferred text binding from overwrite" {
    const source =
        \\make() -> text {
        \\    value = "hello"
        \\    value = "world"
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "gc-root local_bind $value"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "gc-root overwrite $value"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline carries a body-only managed local through a branch" {
    const source =
        \\start() {
        \\    if @eq(1, 1) {
        \\        value text = "hello"
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root local_bind $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a standalone body-only byte-list literal through GC" {
    const source =
        \\start() {
        \\    values [u8] = .{1, 2}
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $values (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a body-only managed struct field read through GC" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    box Box = Box{value = bytes}
        \\    value [u8] = @get(box, .value)
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers inferred managed list storage through GC" {
    const source =
        \\start() {
        \\    seed [u8] = .{1}
        \\    values = @put(seed, 2)
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $values (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root local_bind $values") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a standalone body-only scalar-list literal through GC" {
    const source =
        \\start() {
        \\    values [u32] = .{1, 2}
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $values (ref null $do_u32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_u32 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a bounded body-only scalar-list read through GC" {
    const source =
        \\start() {
        \\    values [u32] = .{1, 2}
        \\    count usize = @len(values)
        \\    item u32 = @get(values, 1)
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $values (ref null $do_u32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.len") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a bounded body-only scalar-list put through GC" {
    const source =
        \\start() {
        \\    values [u32] = .{1, 2}
        \\    values = @put(values, 3)
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $values (ref null $do_u32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_u32 $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a managed-struct list put through GC" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\append(boxes [Box], value Box) -> [Box] {
        \\    return @put(boxes, value)
        \\}
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_list_box $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a bounded body-only scalar-list set through GC" {
    const source =
        \\start() {
        \\    values [u32] = .{1, 2}
        \\    values = @set(values, 1, 3)
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $values (ref null $do_u32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_u32 $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline lowers a direct managed struct identity through GC" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\identity(box Box) -> Box {
        \\    return box
        \\}
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $box (ref null $box))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline fails closed for an unsupported managed candidate" {
    const source =
        \\Box {
        \\    value text
        \\}
        \\replace(values [Box], value Box) -> [Box] {
        \\    return @set(values, 0, value)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.UnsupportedGcSyncType,
        emit_wat_with_options(std.testing.allocator, program, tokens, null, .{}),
    );
}

test "default pipeline lowers a managed parameter with a nil result through GC" {
    const source =
        \\consume(bytes [u8]) -> nil {
        \\    return
        \\}
        \\start() {}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $consume (param $bytes (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $__arc_") == null);
}

test "GC route lowers a reachable imported managed identity" {
    const source =
        \\helper = @lib("./helper.do", helper)
        \\relay(value text) -> text {
        \\    return helper(value)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const imported_tokens = try lexer.tokenize(
        std.testing.allocator,
        "helper(value text) -> text { return value }",
    );
    defer std.testing.allocator.free(imported_tokens);
    var modules = [_]imports.ModuleRecord{
        .{ .path = "./entry.do", .source = null, .owns_source = false, .tokens = tokens, .owns_tokens = false },
        .{ .path = "./helper.do", .source = null, .owns_source = false, .tokens = imported_tokens, .owns_tokens = false },
    };
    var graph = imports.ModuleGraph{ .allocator = std.testing.allocator, .dep_root = "", .modules = modules[0..] };
    const wat = try emit_wat_with_options(std.testing.allocator, program, tokens, &graph, .{ .gc_sync = true });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC route lowers a reachable imported managed struct identity" {
    const source =
        \\Box = @lib("./helper.do", Box)
        \\identity = @lib("./helper.do", identity)
        \\relay(value Box) -> Box {
        \\    return identity(value)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const imported_source =
        \\Box {
        \\    value text
        \\}
        \\identity(value Box) -> Box {
        \\    return value
        \\}
    ;
    const imported_tokens = try lexer.tokenize(std.testing.allocator, imported_source);
    defer std.testing.allocator.free(imported_tokens);
    var modules = [_]imports.ModuleRecord{
        .{ .path = "./entry.do", .source = null, .owns_source = false, .tokens = tokens, .owns_tokens = false },
        .{ .path = "./helper.do", .source = null, .owns_source = false, .tokens = imported_tokens, .owns_tokens = false },
    };
    var graph = imports.ModuleGraph{ .allocator = std.testing.allocator, .dep_root = "", .modules = modules[0..] };
    const wat = try emit_wat_with_options(std.testing.allocator, program, tokens, &graph, .{ .gc_sync = true });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $identity") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $identity") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC route rejects a graph containing an imported host binding" {
    const source =
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const imported_source =
        \\now = @host_func("env", "now", () -> u64)
    ;
    const imported_tokens = try lexer.tokenize(std.testing.allocator, imported_source);
    defer std.testing.allocator.free(imported_tokens);
    var modules = [_]imports.ModuleRecord{
        .{ .path = "./entry.do", .source = null, .owns_source = false, .tokens = tokens, .owns_tokens = false },
        .{ .path = "./clock.do", .source = null, .owns_source = false, .tokens = imported_tokens, .owns_tokens = false },
    };
    var graph = imports.ModuleGraph{ .allocator = std.testing.allocator, .dep_root = "", .modules = modules[0..] };
    try std.testing.expectError(
        error.UnsupportedGcSyncModuleGraph,
        emit_wat_with_options(std.testing.allocator, program, tokens, &graph, .{ .gc_sync = true }),
    );
}

test "GC route rejects a graph containing an imported WIT declaration" {
    const source =
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const imported_source =
        \\Ticket = @wasi_resource("do:gc/ticket", { .id i64 })
    ;
    const imported_tokens = try lexer.tokenize(std.testing.allocator, imported_source);
    defer std.testing.allocator.free(imported_tokens);
    var modules = [_]imports.ModuleRecord{
        .{ .path = "./entry.do", .source = null, .owns_source = false, .tokens = tokens, .owns_tokens = false },
        .{ .path = "./resource.do", .source = null, .owns_source = false, .tokens = imported_tokens, .owns_tokens = false },
    };
    var graph = imports.ModuleGraph{ .allocator = std.testing.allocator, .dep_root = "", .modules = modules[0..] };
    try std.testing.expectError(
        error.UnsupportedGcSyncModuleGraph,
        emit_wat_with_options(std.testing.allocator, program, tokens, &graph, .{ .gc_sync = true }),
    );
}

test "private synchronous GC route emits a bounded payload union" {
    const source =
        \\Message = Empty | Bytes([u8])
        \\rewrite(value Message, bytes [u8]) -> Message {
        \\    return Bytes(bytes)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_wat_with_options(std.testing.allocator, program, tokens, null, .{ .gc_sync = true });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $message") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $message") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "private synchronous GC route emits a resolved generic managed call" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\#T
        \\identity(value T) -> T {
        \\    return value
        \\}
        \\relay(input Box) -> Box {
        \\    return identity(input)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_wat_with_options(std.testing.allocator, program, tokens, null, .{ .gc_sync = true });
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $identity__Box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $identity__Box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "compiled test route emits admitted managed test bodies with GC" {
    const source =
        \\test "compiled text identity preserves value" {
        \\    value text = "hello"
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_test_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $__test_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"__test_0\" (func $__test_0))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"_start\" (func $_start))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root local_bind $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "compiled test route lowers a managed struct list append through GC" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\test "managed struct list append" {
        \\    bytes [u8] = "abc"
        \\    extra [u8] = "def"
        \\    first Box = Box{value = bytes, tag = 7}
        \\    second Box = Box{value = extra, tag = 9}
        \\    boxes [Box] = .{first}
        \\    updated [Box] = @put(boxes, second)
        \\    if @eq(@len(boxes), 1) {
        \\        if @eq(@len(updated), 2) return
        \\    }
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var modules = [_]imports.ModuleRecord{
        .{
            .path = "managed_struct_list_append.do",
            .source = null,
            .owns_source = false,
            .tokens = tokens,
            .owns_tokens = false,
        },
    };
    var graph = imports.ModuleGraph{
        .allocator = std.testing.allocator,
        .dep_root = "",
        .modules = modules[0..],
    };
    const wat = try emit_test_wat(std.testing.allocator, program, tokens, &graph);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_list_box $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "compiled test GC fallback accepts only explicit admission rejections" {
    try std.testing.expect(codegen_gc_sync.is_gc_sync_admission_rejection(error.UnsupportedGcSyncType));
    try std.testing.expect(codegen_gc_sync.is_gc_sync_admission_rejection(error.UnsupportedGcSyncExpression));
    try std.testing.expect(codegen_gc_sync.is_gc_sync_admission_rejection(error.NoMatchingCall));
    try std.testing.expect(!codegen_gc_sync.is_gc_sync_admission_rejection(error.OutOfMemory));
    try std.testing.expect(!codegen_gc_sync.is_gc_sync_admission_rejection(error.UnexpectedResult));
}

test "GC output guard rejects ARC runtime markers" {
    try std.testing.expectError(
        error.GcSyncOutputContainsArc,
        validate_gc_sync_output("(module\\n  call $__arc_dec\\n)"),
    );
}

test "synchronous GC overwrite lowers managed locals without ARC release" {
    const source =
        \\rewrite(value text) -> text {
        \\    next text = value
        \\    next = "changed"
        \\    return next
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try expect_synchronous_gc_locals(wat, "rewrite");
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root overwrite $next") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root return_value") != null);
}

test "synchronous GC marks a managed body binding at its local.set" {
    const source =
        \\rewrite(value text) -> text {
        \\    next text = value
        \\    next = "changed"
        \\    return next
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $next\n    ;; gc-root local_bind $next") != null);
}

test "synchronous GC branch join preserves a managed local" {
    const source =
        \\choose(flag bool, value text) -> text {
        \\    result text = value
        \\    if flag {
        \\        result = "yes"
        \\    } else {
        \\        result = "no"
        \\    }
        \\    return result
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try expect_synchronous_gc_locals(wat, "choose");
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root branch_join") != null);
}

test "synchronous GC loop carries a managed local" {
    const source =
        \\repeat(value text) -> text {
        \\    current text = value
        \\    loop {
        \\        current = value
        \\        break
        \\    }
        \\    return current
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try expect_synchronous_gc_locals(wat, "repeat");
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root loop_join") != null);
}

test "synchronous GC defer return keeps managed locals typed" {
    const source =
        \\finish(value text) -> text {
        \\    defer cleanup()
        \\    return value
        \\}
        \\cleanup() -> nil {}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try expect_synchronous_gc_locals(wat, "finish");
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $cleanup") != null);
}

test "synchronous GC managed call transfers typed values" {
    const source =
        \\identity(value text) -> text {
        \\    return value
        \\}
        \\forward(value text) -> text {
        \\    return identity(value)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try expect_synchronous_gc_locals(wat, "forward");
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $identity") != null);
}

test "synchronous GC marks managed call results as roots" {
    const source =
        \\make() -> text {
        \\    return "created"
        \\}
        \\forward() -> text {
        \\    result text = make()
        \\    return result
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root call_result") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC marks payload-union call results as roots" {
    const source =
        \\Message = Empty | Bytes([u8])
        \\make(value [u8]) -> Message {
        \\    return Bytes(value)
        \\}
        \\forward(value [u8]) -> Message {
        \\    return make(value)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root call_result") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default compiled pipeline lowers a bounded payload-union construction through GC" {
    const source =
        \\Message = Empty | Bytes([u8])
        \\make(value [u8]) -> Message {
        \\    return Bytes(value)
        \\}
        \\start() {}
        \\test "compiled payload union construction" {
        \\    bytes [u8] = .{1, 2}
        \\    make(bytes)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_test_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $message") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $message") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default pipeline declares a typed GC array for a start-local scalar list" {
    const source =
        \\start() {
        \\    xs [i32] = .{10, 20, 30}
        \\    count usize = @len(xs)
        \\    value i32 = @get(xs, 1)
        \\    return
        \\}
    ;
    const wat = try emit_default_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_i32 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "default synchronous pipeline guards converted control and call paths" {
    const cases = [_]struct {
        source: []const u8,
        function_name: []const u8,
        expect_gc: bool,
    }{
        .{
            .source =
            \\rewrite(value text) -> text {
            \\    next text = value
            \\    next = "changed"
            \\    return next
            \\}
            \\start() {}
            ,
            .function_name = "rewrite",
            .expect_gc = true,
        },
        .{
            .source =
            \\choose(flag bool, value text) -> text {
            \\    result text = value
            \\    if flag {
            \\        result = "yes"
            \\    } else {
            \\        result = "no"
            \\    }
            \\    return result
            \\}
            \\start() {}
            ,
            .function_name = "choose",
            .expect_gc = true,
        },
        .{
            .source =
            \\repeat(value text) -> text {
            \\    current text = value
            \\    loop {
            \\        current = value
            \\        break
            \\    }
            \\    return current
            \\}
            \\start() {}
            ,
            .function_name = "repeat",
            .expect_gc = true,
        },
        .{
            .source =
            \\finish(value text) -> text {
            \\    defer cleanup()
            \\    return value
            \\}
            \\cleanup() -> nil {}
            \\start() {}
            ,
            .function_name = "finish",
            .expect_gc = true,
        },
        .{
            .source =
            \\identity(value text) -> text {
            \\    return value
            \\}
            \\forward(value text) -> text {
            \\    return identity(value)
            \\}
            \\start() {}
            ,
            .function_name = "forward",
            .expect_gc = true,
        },
    };

    for (cases) |case| {
        const wat = try emit_default_wat_for_source(std.testing.allocator, case.source);
        defer std.testing.allocator.free(wat);
        if (case.expect_gc) {
            try expect_synchronous_gc_locals(wat, case.function_name);
            try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_alloc") == null);
        } else {
            try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_alloc") != null);
        }
    }
}

test "default synchronous pipeline guards converted managed aggregates" {
    const cases = [_][]const u8{
        \\Box {
        \\    value text
        \\    tag i32
        \\}
        \\update(box Box, value text) -> Box {
        \\    return @set(box, .value, value)
        \\}
        \\start() {}
        ,
        \\Message = Empty | Bytes([u8])
        \\rewrite(value Message, bytes [u8]) -> Message {
        \\    return Bytes(bytes)
        \\}
        \\start() {}
        ,
        \\rewrite(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> {
        \\    return Tuple<text, [u8]>{@get(pair, 0), @set(@get(pair, 1), 0, 65)}
        \\}
        \\start() {}
        ,
    };

    for (cases) |source| {
        const wat = try emit_default_wat_for_source(std.testing.allocator, source);
        defer std.testing.allocator.free(wat);
        try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new") != null);
        try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_inc") == null);
        try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_dec") == null);
        try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_payload") == null);
        try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_alloc") == null);
    }
}

test "synchronous GC parses renamed parameterized byte-list persistent update" {
    const source =
        \\replace(bytes [u8], offset usize, next u8) -> [u8] {
        \\    return @set(bytes, offset, next)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $replace") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.len\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $offset") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $next") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
}

test "synchronous GC reserves byte-list update temporaries away from source bindings" {
    const source =
        \\replace(__gc_list_next [u8], __gc_list_length usize, next u8) -> [u8] {
        \\    return @set(__gc_list_next, __gc_list_length, next)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $__gc_list_next (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $__gc_list_next_1 (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $__gc_list_length_1 i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
}

test "synchronous GC lowers parsed byte-list literal" {
    const source =
        \\make() -> [u8] {
        \\    return .{7, 12, 17}
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 7\n    i32.const 12\n    i32.const 17") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC lowers empty parsed byte-list literal" {
    const source =
        \\make() -> [u8] {
        \\    return .{}
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0\n    array.new_default $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC rejects byte-list literal values outside u8" {
    const high_source =
        \\make() -> [u8] {
        \\    return .{256}
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.GcSyncTypeMismatch, emit_gc_wat_for_source(std.testing.allocator, high_source));

    const negative_source =
        \\make() -> [u8] {
        \\    return .{-1}
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.GcSyncTypeMismatch, emit_gc_wat_for_source(std.testing.allocator, negative_source));
}

test "synchronous GC keeps byte-list put outside the literal slice" {
    const source =
        \\replace(input [u8], index usize, value u8) -> [u8] {
        \\    return @put(input, index, value)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncExpression, emit_gc_wat_for_source(std.testing.allocator, source));
}

test "synchronous GC lowers one-value byte-list put" {
    const source =
        \\append_byte(input [u8], value u8) -> [u8] {
        \\    return @put(input, value)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC lowers one-value scalar-list put" {
    const source =
        \\append_word(input [u32], value u32) -> [u32] {
        \\    return @put(input, value)
        \\}
        \\append_float(input [f64], value f64) -> [f64] {
        \\    return @put(input, value)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_f64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_f64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC rejects byte-list put spread and multiple values" {
    const multiple_source =
        \\append_byte(input [u8]) -> [u8] {
        \\    return @put(input, 1, 2)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncExpression, emit_gc_wat_for_source(std.testing.allocator, multiple_source));

    const spread_source =
        \\append_byte(input [u8], values [u8]) -> [u8] {
        \\    return @put(input, ...values)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncExpression, emit_gc_wat_for_source(std.testing.allocator, spread_source));
}

test "synchronous GC rejects byte-list put values outside u8" {
    const high_source =
        \\append_byte(input [u8]) -> [u8] {
        \\    return @put(input, 256)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.GcSyncTypeMismatch, emit_gc_wat_for_source(std.testing.allocator, high_source));

    const negative_source =
        \\append_byte(input [u8]) -> [u8] {
        \\    return @put(input, -1)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.GcSyncTypeMismatch, emit_gc_wat_for_source(std.testing.allocator, negative_source));
}

test "synchronous GC rejects non-u8 byte-list put values" {
    const source =
        \\append_value(input [u8], value i32) -> [u8] {
        \\    return @put(input, value)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncType, emit_gc_wat_for_source(std.testing.allocator, source));
}

test "synchronous GC lowers managed-element list put" {
    const source =
        \\append_value(input [text], value text) -> [text] {
        \\    return @put(input, value)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_list_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_list_text $do_list_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_list_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC backend admits text-element list identity" {
    const source =
        \\unsupported(value [text]) -> [text] {
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_list_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $value (ref null $do_list_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_list_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC lowers a managed struct identity" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\identity(box Box) -> Box {
        \\    return box
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box (struct (field $value (ref null $do_bytes))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $box (ref null $box))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $box))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC preserves scalar fields in a managed struct identity" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\identity(box Box) -> Box {
        \\    return box
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box (struct (field $value (ref null $do_bytes)) (field $tag i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $box (ref null $box))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $box))") != null);
}

test "synchronous GC declares nested managed structs before their users" {
    const source =
        \\Outer {
        \\    inner Inner
        \\    tag i32
        \\}
        \\Inner {
        \\    value [u8]
        \\}
        \\identity(box Outer) -> Outer {
        \\    return box
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    const inner = std.mem.indexOf(u8, wat, "(type $inner ") orelse return error.TestExpectedEqual;
    const outer = std.mem.indexOf(u8, wat, "(type $outer ") orelse return error.TestExpectedEqual;
    try std.testing.expect(inner < outer);
}

test "synchronous GC reads a scalar field from a managed struct" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\read(box Box) -> i32 {
        \\    return @get(box, .tag)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "ref.as_non_null\n    struct.get $box $tag") != null);
}

test "synchronous GC rebuilds a managed struct for scalar field update" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\update(box Box) -> Box {
        \\    return @set(box, .tag, 7)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 7\n    struct.new $box") != null);
}

test "synchronous GC rebuilds a managed field with a new payload" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\update(box Box, value [u8]) -> Box {
        \\    return @set(box, .value, value)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC rebuilds a text managed field payload" {
    const source =
        \\Box {
        \\    value text
        \\}
        \\update(box Box, value text) -> Box {
        \\    return @set(box, .value, value)
        \\}
        \\start() {}
    ;
    const wat = try emit_gc_wat_for_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "synchronous GC rejects nested managed field payload producer" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\update(box Box) -> Box {
        \\    return @set(box, .value, .{1, 2})
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncProducer, emit_gc_wat_for_source(std.testing.allocator, source));
}

fn emit_gc_wat_for_source(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);
    return codegen_gc_sync.emit_gc_wat_for_supported_program(allocator, program, tokens, null);
}

fn emit_default_wat_for_source(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);
    return emit_wat_with_options(allocator, program, tokens, null, .{});
}

fn expect_synchronous_gc_locals(wat: []const u8, function_name: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, wat, function_name) != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_text)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_inc") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_dec") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_payload") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_alloc") == null);
}

pub fn emit_wat_with_options(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph, options: EmitOptions) ![]u8 {
    if (options.p3_resource_probe_component) return finalize_component_wat(allocator, codegen_component_resource_probe.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_wasi_filesystem_preopen_component) return finalize_component_wat(allocator, codegen_component_wasi_filesystem_preopen.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_wasi_sockets_create_bind_drop_component) return finalize_component_wat(allocator, codegen_component_wasi_sockets.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_resource_async_component) return finalize_component_wat(allocator, codegen_component_resource_async.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_async_call_component) {
        var plan = codegen_component_async.analyze_async_call_component(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncCallComponent => return error.UnsupportedP3AsyncCallComponent,
            else => return err,
        };
        defer plan.deinit(allocator);
        return codegen_component_async_call.emit_component_wat(allocator, plan);
    }
    if (options.p3_async_host_arg_component) {
        var plan = codegen_component_async_host_arg_plan.analyze(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHostArgComponent => return error.UnsupportedP3AsyncHostArgComponent,
            else => return err,
        };
        defer plan.deinit(allocator);
        return codegen_component_async_host_arg.emit_component_wat(allocator, plan);
    }
    if (options.p3_owned_future_component) {
        var plan = codegen_component_future_owned_plan.analyze(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3OwnedFutureComponent => return error.UnsupportedP3OwnedFutureComponent,
            else => return err,
        };
        defer plan.deinit(allocator);
        return codegen_component_future_owned.emit_component_wat(allocator, plan);
    }
    if (options.p3_async_component_v2) return codegen_component_async.emit_component_wat_v2(allocator, program, tokens, module_graph);
    if (options.p3_async_v2_scalar_i64_component) return finalize_component_wat(allocator, codegen_component_async.emit_component_wat_v2_scalar_i64(allocator, program, tokens, module_graph orelse return error.UnsupportedP3AsyncComponent));
    if (options.p3_wasi_filesystem_stat_component) {
        const target = codegen_component_async.target_for_tokens_with_graph(allocator, tokens, module_graph) catch
            return error.UnsupportedP3AsyncComponent;
        if (target != .wasi_filesystem_stat) return error.UnsupportedP3AsyncComponent;
        return codegen_component_async.emit_component_wat(allocator, program, tokens, module_graph);
    }
    if (options.p3_async_component) return codegen_component_async.emit_component_wat(allocator, program, tokens, module_graph);
    if (options.gc_sync) return emit_checked_gc_sync(allocator, program, tokens, module_graph);
    if (options.gc_core) return codegen_gc_core.emit_gc_core_wat(allocator, program, tokens);

    if (options.p3_wait_for_component) return finalize_component_wat(allocator, codegen_p3_wait_for.emit_component_wat(allocator, program, tokens, module_graph));
    if (try codegen_task_bridge.emit_if_supported(allocator, program, tokens)) |wat| return wat;
    if (try codegen_emit_generic_async.emit_if_supported(allocator, program, tokens, module_graph)) |wat| return wat;
    // Generic Core-Wasm emission has no resumable async lowering. Guard before
    // any body-dependent collection can misclassify an async intrinsic call.
    if (program_requires_async_lowering(program, tokens, module_graph)) return error.AsyncLoweringUnavailable;
    // GC admission may collect concrete function bodies through the shared
    // generic/reflection helpers, so install the normal generation hooks before
    // entering the GC route as well as before the legacy emitter below.
    install_gen_hooks();
    if (!options.host_export) {
        if (try try_emit_default_gc_sync(allocator, program, tokens, module_graph)) |wat| return wat;
    }

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
        free_wasi_host_imports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try collect_wasi_host_imports_from_modules(allocator, graph.modules, tokens, &wasi_imports);
    } else {
        try collect_wasi_host_imports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &wasi_imports);
    }
    var entry_wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        free_wasi_host_imports(allocator, entry_wasi_imports.items);
        entry_wasi_imports.deinit(allocator);
    }
    try collect_wasi_host_imports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &entry_wasi_imports);
    try validate_wasi_host_import_build_uses(tokens, entry_wasi_imports.items);
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
    const async_functions = try codegen_async_model.collect_async_functions(allocator, functions.items);
    defer codegen_async_model.free_async_function_plans(allocator, async_functions);
    const ctx = CodegenContext{
        .functions = functions.items,
        .async_functions = async_functions,
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
    if (options.host_manifest_out) |manifest_out| {
        const manifest = try host_export_manifest.emit(allocator, functions.items, tokens, ctx);
        defer allocator.free(manifest);
        try manifest_out.appendSlice(allocator, manifest);
    }

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
    if (options.host_export) {
        try emit_host_exports(allocator, ctx, &out);
    } else {
        try emit_start_func(allocator, tokens, ctx, &out);
    }
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

fn finalize_component_wat(allocator: std.mem.Allocator, result: anyerror![]u8) ![]u8 {
    const wat = result catch |err| return err;
    const rewritten = codegen_component_cabi_realloc.rewrite(allocator, wat) catch |err| {
        allocator.free(wat);
        return err;
    };
    allocator.free(wat);
    return rewritten;
}

pub fn emit_test_wat(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token, module_graph: ?*const imports.ModuleGraph) ![]u8 {
    install_gen_hooks();

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    const test_decls = try test_runner.collect_top_level_tests(allocator, tokens);
    defer allocator.free(test_decls);
    if (test_decls.len == 0) return error.NoTestDecl;

    // GC-first migration bridge: admitted synchronous compiled tests use the
    // typed GC emitter. Unsupported test shapes continue through the existing
    // ARC path until the later default cutover gate closes.
    // Scalar-only compiled tests have no managed GC candidate. Keep them on
    // the existing ARC/TCO path until the global GC cutover; attempting the
    // GC emitter here would silently lose backend-specific lowering such as
    // self-tail loops and field reflection.
    if (tokens_have_gc_sync_candidate(tokens) or tokens_have_gc_sync_test_candidate(tokens)) {
        if (codegen_gc_sync.emit_gc_wat_for_supported_tests(allocator, program, tokens, module_graph) catch |err| blk: {
            if (!codegen_gc_sync.is_gc_sync_admission_rejection(err)) return err;
            break :blk null;
        }) |gc_wat| {
            validate_gc_sync_output(gc_wat) catch |err| {
                allocator.free(gc_wat);
                return err;
            };
            return gc_wat;
        }
    }

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
        free_wasi_host_imports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try collect_wasi_host_imports_from_modules(allocator, graph.modules, tokens, &wasi_imports);
    } else {
        try collect_wasi_host_imports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &wasi_imports);
    }
    var entry_wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        free_wasi_host_imports(allocator, entry_wasi_imports.items);
        entry_wasi_imports.deinit(allocator);
    }
    try collect_wasi_host_imports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &entry_wasi_imports);
    try validate_wasi_host_import_build_uses(tokens, entry_wasi_imports.items);
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
    const async_functions = try codegen_async_model.collect_async_functions(allocator, functions.items);
    defer codegen_async_model.free_async_function_plans(allocator, async_functions);

    const ctx = CodegenContext{
        .functions = functions.items,
        .async_functions = async_functions,
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
        try append_mangled_type_name(allocator, &out, param.ty);
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
