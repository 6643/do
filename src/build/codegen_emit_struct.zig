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
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const gen_ownership = @import("gen_ownership.zig");
const find_top_level_guard_loop_control = gen_ownership.findTopLevelGuardLoopControl;
const label_for_loop_start = gen_ownership.labelForLoopStart;
const find_value_enum_decl_line_by_name = gen_import.findValueEnumDeclLineByName;
const find_value_enum_decl_line_by_branch = gen_import.findValueEnumDeclLineByBranch;
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
const string_literal_arg_lexeme = codegen_tokens.string_literal_arg_lexeme;
const is_string_literal_arg = codegen_tokens.is_string_literal_arg;
const decode_quoted_string_token = codegen_tokens.decode_quoted_string_token;
const find_token = codegen_tokens.find_token;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const find_stmt_end = codegen_tokens.find_stmt_end;
const find_type_arg_end = codegen_tokens.find_type_arg_end;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const module_scoped_symbol_name = codegen_names.module_scoped_symbol_name;
const append_mangled_type_name = codegen_names.append_mangled_type_name;
const is_user_func_decl_start = codegen_tokens.is_user_func_decl_start;
const is_public_type_name = codegen_names.is_public_type_name;
const is_error_type_name = codegen_names.is_error_type_name;
const is_base_int_type_name = codegen_names.is_base_int_type_name;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;
const is_core_integer_scalar = codegen_names.is_core_integer_scalar;
const is_core_float_scalar = codegen_names.is_core_float_scalar;
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
const token_text_equals_compact = codegen_tokens.token_text_equals_compact;
const find_top_level_type_separator = codegen_tokens.find_top_level_type_separator;
const find_top_level_type_separator_from = codegen_tokens.find_top_level_type_separator_from;
const has_string = codegen_names.has_string;

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
const find_local_type = context.findLocalType;
const find_local_origin = context.findLocalOrigin;
const find_storage_local = context.findStorageLocal;
const find_struct_local = context.findStructLocal;
const find_union_local = context.findUnionLocal;
const has_local = context.hasLocal;
const is_compiler_local_name = context.isCompilerLocalName;
const storage_type_name_for_elem = context.storageTypeNameForElem;
const storage_type_name_for_elem_owned = context.storageTypeNameForElemOwned;
const local_name_matches = context.localNameMatches;
const union_payload_local_name = context.unionPayloadLocalName;
const union_tag_local_name = context.unionTagLocalName;

const UnionLayout = codegen_union_layout.UnionLayout;
const UnionBranch = codegen_union_layout.UnionBranch;
const free_union_layout = codegen_union_layout.free_union_layout;
const clone_union_layout = codegen_union_layout.clone_union_layout;
const union_layouts_equal = codegen_union_layout.union_layouts_equal;
const union_branch_is_status_i32 = codegen_union_layout.union_branch_is_status_i32;

const find_struct_decl = gen_collect_util.findStructDecl;
const find_struct_layout = gen_collect_util.findStructLayout;
const find_struct_layout_exact = codegen_collect_structs.find_struct_layout_exact;
const is_pack_managed_handle_leaf = codegen_collect_structs.is_pack_managed_handle_leaf;
const leaf_payload_bytes_for_pack = codegen_collect_structs.leaf_payload_bytes_for_pack;
const pure_scalar_struct_pack_width = gen_collect_util.pureScalarStructPackWidth;
const pack_slot_width = gen_collect_util.packSlotWidth;
const tuple_pack_width_with_structs = gen_collect_util.tuplePackWidthWithStructs;
const append_tuple_leaf_types_with_structs = gen_collect_util.appendTupleLeafTypesWithStructs;
const append_tuple_leaf_types = gen_collect_util.appendTupleLeafTypes;
const struct_decl_has_managed_field = gen_collect_util.structDeclHasManagedField;
const ensure_storage_pack_layout = codegen_collect_structs.ensure_storage_pack_layout;
const managed_leaf_field_name = codegen_collect_structs.managed_leaf_field_name;
const is_error_like_type = gen_collect_util.isErrorLikeType;
const parse_codegen_type_expr = gen_collect_util.parseCodegenTypeExpr;
const parse_type_union_layout_from_name = codegen_collect_structs.parse_type_union_layout_from_name;
const bind_struct_type_args = codegen_collect_structs.bind_struct_type_args;
const substitute_generic_type_owned = gen_collect_util.substituteGenericTypeOwned;
const find_generic_binding = gen_collect_util.findGenericBinding;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const func_param_abi_type = gen_collect_util.funcParamAbiType;
const is_unmanaged_scalar_struct = gen_collect_util.isUnmanagedScalarStruct;
const append_union_branch_payload_types = gen_collect_util.appendUnionBranchPayloadTypes;

const call_head_at = gen_import.callHeadAt;
const expr_call_head = gen_import.exprCallHead;
const call_head_has_type_args = gen_import.callHeadHasTypeArgs;
const find_value_enum_decl = gen_import.findValueEnumDecl;
const find_codegen_import_by_alias = gen_import.findCodegenImportByAlias;
const imported_alias_context_for_tokens = gen_import.importedAliasContextForTokens;
const local_scalar_const = gen_import.localScalarConst;
const imported_scalar_const = gen_import.importedScalarConst;
const find_imported_module_index = gen_import.findImportedModuleIndex;
const find_imported_module_index_no_alloc = gen_import.findImportedModuleIndexNoAlloc;
const find_wasi_host_import_for_tokens = gen_import.findWasiHostImportForTokens;
const wasi_source_for_tokens = gen_import.wasiSourceForTokens;

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
const is_tuple_packable_leaf_type = type_util.isTuplePackableLeafType;
const is_core_wasm_scalar_tu = type_util.isCoreWasmScalar;

const host_param_is_ptr_len = gen_host.hostParamIsPtrLen;
const host_arg_could_be_storage_ptr_len_syntax = gen_host.hostArgCouldBeStoragePtrLenSyntax;
const find_host_import_for_tokens = gen_host.findHostImportForTokens;

const WasiHostImport = codegen_wasi_registry.WasiHostImport;

const codegen_emit_storage_values = @import("codegen_emit_storage_values.zig");
const emit_storage_binding = codegen_emit_storage_values.emit_storage_binding;
const emit_storage_handle_assignment_expr = codegen_emit_storage_values.emit_storage_handle_assignment_expr;
const emit_tuple_binding = codegen_emit_storage_values.emit_tuple_binding;
const emit_storage_assignment = codegen_emit_storage_values.emit_storage_assignment;
const stmt_contains_storage_agg_literal = codegen_emit_storage_values.stmt_contains_storage_agg_literal;
const emit_storage_agg_return_value = codegen_emit_storage_values.emit_storage_agg_return_value;
const emit_tuple_return_local = codegen_emit_storage_values.emit_tuple_return_local;
const emit_tuple_return_expr = codegen_emit_storage_values.emit_tuple_return_expr;
const emit_storage_u8_string_literal = codegen_emit_storage_values.emit_storage_u8_string_literal;
const emit_storage_u8_string_literal_value = codegen_emit_storage_values.emit_storage_u8_string_literal_value;
const emit_storage_u8_raw_string_value = codegen_emit_storage_values.emit_storage_u8_raw_string_value;
const emit_storage_u8_string_literal_into_local = codegen_emit_storage_values.emit_storage_u8_string_literal_into_local;
const emit_storage_agg_literal = codegen_emit_storage_values.emit_storage_agg_literal;
const is_storage_agg_literal_expr = codegen_emit_storage_values.is_storage_agg_literal_expr;
const count_agg_literal_items = codegen_emit_storage_values.count_agg_literal_items;
const emit_storage_payload_ptr = codegen_emit_storage_values.emit_storage_payload_ptr;
const emit_storage_len_ptr_with_indent = codegen_emit_storage_values.emit_storage_len_ptr_with_indent;
const emit_storage_cap_ptr = codegen_emit_storage_values.emit_storage_cap_ptr;
const emit_storage_cap_ptr_with_indent = codegen_emit_storage_values.emit_storage_cap_ptr_with_indent;
const emit_storage_payload_ptr_with_indent = codegen_emit_storage_values.emit_storage_payload_ptr_with_indent;
const emit_tuple_local_set = codegen_emit_storage_values.emit_tuple_local_set;
const emit_tuple_local_get = codegen_emit_storage_values.emit_tuple_local_get;
const emit_tuple_get_binding = codegen_emit_storage_values.emit_tuple_get_binding;
const emit_storage_content_comparison_call = codegen_emit_storage_values.emit_storage_content_comparison_call;
const emit_managed_payload_storage_content_comparison_call = codegen_emit_storage_values.emit_managed_payload_storage_content_comparison_call;
const infer_storage_content_comparison_type = codegen_emit_storage_values.infer_storage_content_comparison_type;
const storage_content_arg_compatible = codegen_emit_storage_values.storage_content_arg_compatible;
const is_managed_payload_comparable_type = codegen_emit_storage_values.is_managed_payload_comparable_type;
const emit_storage_ptr_len_host_arg = codegen_emit_storage_values.emit_storage_ptr_len_host_arg;
const emit_tuple_expr = codegen_emit_storage_values.emit_tuple_expr;
const storage_binding_elem_type = codegen_emit_storage_values.storage_binding_elem_type;
const managed_payload_binding = codegen_emit_storage_values.managed_payload_binding;
const parse_storage_type = codegen_emit_storage_values.parse_storage_type;
const emit_storage_bounds_check = codegen_emit_storage_values.emit_storage_bounds_check;
const emit_storage_write_expr = codegen_emit_storage_values.emit_storage_write_expr;
const emit_storage_set_expr = codegen_emit_storage_values.emit_storage_set_expr;
const emit_storage_put_call = codegen_emit_storage_values.emit_storage_put_call;
const emit_storage_put_expr = codegen_emit_storage_values.emit_storage_put_expr;
const emit_storage_put_spread_call = codegen_emit_storage_values.emit_storage_put_spread_call;
const emit_storage_set_scalar_call = codegen_emit_storage_values.emit_storage_set_scalar_call;
const emit_storage_put_spread_scalar_element = codegen_emit_storage_values.emit_storage_put_spread_scalar_element;
const emit_storage_put_scalar_call = codegen_emit_storage_values.emit_storage_put_scalar_call;
const emit_storage_clone_current_len = codegen_emit_storage_values.emit_storage_clone_current_len;
const emit_storage_clone_current_len_for_elem = codegen_emit_storage_values.emit_storage_clone_current_len_for_elem;
const emit_storage_clone_managed_current_len = codegen_emit_storage_values.emit_storage_clone_managed_current_len;
const emit_storage_clone_managed_with_len_local = codegen_emit_storage_values.emit_storage_clone_managed_with_len_local;
const emit_storage_inc_copied_managed_elements = codegen_emit_storage_values.emit_storage_inc_copied_managed_elements;
const emit_storage_clone_with_len_local = codegen_emit_storage_values.emit_storage_clone_with_len_local;
const emit_storage_clone_with_len_local_for_elem = codegen_emit_storage_values.emit_storage_clone_with_len_local_for_elem;
const emit_storage_clone_with_len_local_typed = codegen_emit_storage_values.emit_storage_clone_with_len_local_typed;
const emit_storage_inc_copied_pack_elements = codegen_emit_storage_values.emit_storage_inc_copied_pack_elements;
const emit_storage_element_ptr_from_local = codegen_emit_storage_values.emit_storage_element_ptr_from_local;
const emit_storage_element_ptr_from_local_with_indent = codegen_emit_storage_values.emit_storage_element_ptr_from_local_with_indent;
const emit_storage_alias_protect = codegen_emit_storage_values.emit_storage_alias_protect;
const emit_storage_alias_release = codegen_emit_storage_values.emit_storage_alias_release;
const emit_empty_storage_u8_value = codegen_emit_storage_values.emit_empty_storage_u8_value;
const emit_empty_storage_for_elem_type = codegen_emit_storage_values.emit_empty_storage_for_elem_type;
const storage_element_byte_width_for_type = codegen_emit_storage_values.storage_element_byte_width_for_type;
const tuple_pack_spill_local = codegen_emit_storage_values.tuple_pack_spill_local;
const append_store_tuple_scalar_leaves_from_stack = codegen_emit_storage_values.append_store_tuple_scalar_leaves_from_stack;
const append_store_tuple_scalar_leaves_from_stack_ctx = codegen_emit_storage_values.append_store_tuple_scalar_leaves_from_stack_ctx;
const append_store_tuple_leaves_owning_from_stack = codegen_emit_storage_values.append_store_tuple_leaves_owning_from_stack;
const append_store_tuple_leaves_owning_from_stack_ctx = codegen_emit_storage_values.append_store_tuple_leaves_owning_from_stack_ctx;
const append_inc_managed_tuple_leaves_on_stack_ctx = codegen_emit_storage_values.append_inc_managed_tuple_leaves_on_stack_ctx;
const append_load_tuple_scalar_leaves_to_stack = codegen_emit_storage_values.append_load_tuple_scalar_leaves_to_stack;
const append_load_tuple_scalar_leaves_to_stack_ctx = codegen_emit_storage_values.append_load_tuple_scalar_leaves_to_stack_ctx;
const append_load_tuple_leaves_owning_to_stack = codegen_emit_storage_values.append_load_tuple_leaves_owning_to_stack;
const append_load_tuple_leaves_owning_to_stack_ctx = codegen_emit_storage_values.append_load_tuple_leaves_owning_to_stack_ctx;
const append_load_tuple_element_from_packed_base_ctx = codegen_emit_storage_values.append_load_tuple_element_from_packed_base_ctx;
const append_load_tuple_leaf_types_of_struct_to_stack = codegen_emit_storage_values.append_load_tuple_leaf_types_of_struct_to_stack;
const append_load_tuple_element_owning_from_packed_base = codegen_emit_storage_values.append_load_tuple_element_owning_from_packed_base;
const emit_inc_managed_tuple_leaves_at_base = codegen_emit_storage_values.emit_inc_managed_tuple_leaves_at_base;
const emit_dec_managed_tuple_leaves_at_base = codegen_emit_storage_values.emit_dec_managed_tuple_leaves_at_base;
const emit_number_const = codegen_emit_storage_values.emit_number_const;
const append_store_for_payload_type = codegen_emit_storage_values.append_store_for_payload_type;
const append_store_for_payload_type_with_indent = codegen_emit_storage_values.append_store_for_payload_type_with_indent;
const append_load_for_payload_type_with_indent = codegen_emit_storage_values.append_load_for_payload_type_with_indent;
const emit_tuple_field_path_get_call = codegen_emit_storage_values.emit_tuple_field_path_get_call;
const emit_pure_scalar_struct_local_set = codegen_emit_storage_values.emit_pure_scalar_struct_local_set;
const emit_pure_scalar_struct_local_get = codegen_emit_storage_values.emit_pure_scalar_struct_local_get;
const single_tuple_result_item = codegen_emit_storage_values.single_tuple_result_item;
const is_direct_managed_local_expr = codegen_emit_storage_values.is_direct_managed_local_expr;
const storage_pack_layout_for_elem = codegen_emit_storage_values.storage_pack_layout_for_elem;
const tuple_element_pack_offset_with_structs = codegen_emit_storage_values.tuple_element_pack_offset_with_structs;
const tuple_field_path_type = codegen_emit_storage_values.tuple_field_path_type;
const find_struct_literal_field = codegen_emit_storage_values.find_struct_literal_field;
const substitute_struct_field_type = codegen_emit_storage_values.substitute_struct_field_type;
const is_struct_literal_rhs = codegen_emit_storage_values.is_struct_literal_rhs;
const emit_replace_storage_put_source_tmp = codegen_emit_storage_values.emit_replace_storage_put_source_tmp;
const direct_managed_local_expr_name = codegen_emit_storage_values.direct_managed_local_expr_name;
const emit_overwrite_release_managed_local = codegen_emit_storage_values.emit_overwrite_release_managed_local;
const find_local_field_type = codegen_emit_storage_values.find_local_field_type;
const tuple_get_element_info = codegen_emit_storage_values.tuple_get_element_info;
const find_func_decl_for_call_head = codegen_storage_layout.find_func_decl_for_call_head;
const infer_expr_type = codegen_emit_storage_values.infer_expr_type;
const find_struct_literal_field_end = codegen_emit_storage_values.find_struct_literal_field_end;
const find_struct_field_type = codegen_emit_storage_values.find_struct_field_type;
const local_field_name_matches = codegen_emit_storage_values.local_field_name_matches;
const direct_managed_last_use_move_source = codegen_emit_storage_values.direct_managed_last_use_move_source;
const struct_literal_open_rhs = codegen_emit_storage_values.struct_literal_open_rhs;
const union_payload_local_name_from_locals = codegen_emit_storage_values.union_payload_local_name_from_locals;
const substitute_generic_type = codegen_emit_storage_values.substitute_generic_type;
const is_union_payload_local_name = codegen_emit_storage_values.is_union_payload_local_name;
const find_callback_call_arg = codegen_emit_storage_values.find_callback_call_arg;
const append_tuple_local_fields_borrowed = codegen_emit_storage_values.append_tuple_local_fields_borrowed;
const find_func_decl_for_call = codegen_emit_storage_values.find_func_decl_for_call;
const find_local_name = codegen_emit_storage_values.find_local_name;
const emit_storage_set_call = codegen_emit_storage_values.emit_storage_set_call;
const emit_storage_put_one_call = codegen_emit_storage_values.emit_storage_put_one_call;
const call_explicit_type_args_match_bindings = codegen_emit_storage_values.call_explicit_type_args_match_bindings;
const call_args_match_func_params = codegen_emit_storage_values.call_args_match_func_params;
const has_registered_defer_stmt = codegen_emit_storage_values.has_registered_defer_stmt;
const append_borrowed_local_field = codegen_emit_storage_values.append_borrowed_local_field;
const token_range_uses_ident = codegen_emit_storage_values.token_range_uses_ident;
const should_infer_bool_special_call = codegen_emit_storage_values.should_infer_bool_special_call;
const is_defer_stmt = codegen_emit_storage_values.is_defer_stmt;
const call_arg_matches_callback_shape = codegen_emit_storage_values.call_arg_matches_callback_shape;
const emit_storage_set_managed_call = codegen_emit_storage_values.emit_storage_set_managed_call;
const emit_storage_put_managed_call = codegen_emit_storage_values.emit_storage_put_managed_call;
const emit_managed_storage_value = codegen_emit_storage_values.emit_managed_storage_value;
const infer_scalar_as_call_type = codegen_emit_storage_values.infer_scalar_as_call_type;
const find_callback_binding = codegen_storage_layout.find_callback_binding;
const scalar_as_target_type = codegen_emit_storage_values.scalar_as_target_type;
const call_arg_matches_concrete_callback_binding = codegen_emit_storage_values.call_arg_matches_concrete_callback_binding;
const is_scalar_as_target_type_name = codegen_emit_storage_values.is_scalar_as_target_type_name;
const infer_set_call_type = codegen_emit_storage_values.infer_set_call_type;
const callback_bindings_have_same_shape = codegen_storage_layout.callback_bindings_have_same_shape;
const call_arg_matches_param = codegen_storage_layout.call_arg_matches_param;
const infer_put_call_type = codegen_emit_storage_values.infer_put_call_type;
const call_args_match_variadic_tail = codegen_storage_layout.call_args_match_variadic_tail;
const call_arg_matches_union_param = codegen_emit_storage_values.call_arg_matches_union_param;
const union_type_name_has_branch = codegen_emit_storage_values.union_type_name_has_branch;
const infer_field_get_call_type = codegen_emit_storage_values.infer_field_get_call_type;
const func_variadic_elem_type = codegen_storage_layout.func_variadic_elem_type;
const infer_field_set_call_type = codegen_emit_storage_values.infer_field_set_call_type;
const find_field_meta_local = codegen_emit_storage_values.find_field_meta_local;
const struct_literal_expr_matches_type = codegen_emit_storage_values.struct_literal_expr_matches_type;
const infer_get_call_type = codegen_emit_storage_values.infer_get_call_type;
const lambda_expr_shape = codegen_storage_layout.lambda_expr_shape;
const lambda_param_count = codegen_emit_storage_values.lambda_param_count;
const callback_binding_has_same_concrete_arg = codegen_storage_layout.callback_binding_has_same_concrete_arg;
const value_enum_branch_value = codegen_emit_storage_values.value_enum_branch_value;
const infer_tuple_field_path_get_type = codegen_emit_storage_values.infer_tuple_field_path_get_type;
const append_managed_struct_field_meta_local = codegen_emit_storage_values.append_managed_struct_field_meta_local;
const field_from_meta = codegen_emit_storage_values.field_from_meta;
const find_struct_field = codegen_emit_storage_values.find_struct_field;
const union_local_default_payload_type = codegen_emit_storage_values.union_local_default_payload_type;
const union_local_default_struct_payload = codegen_emit_storage_values.union_local_default_struct_payload;
const find_narrowed_union_type = codegen_emit_storage_values.find_narrowed_union_type;
const is_dot_ident = codegen_emit_storage_values.is_dot_ident;
const is_arrow_at = codegen_emit_storage_values.is_arrow_at;
const lambda_body_start = codegen_emit_storage_values.lambda_body_start;
const lambda_param_type_name = codegen_emit_storage_values.lambda_param_type_name;
const lambda_explicit_return_type = codegen_emit_storage_values.lambda_explicit_return_type;
const append_typed_local_with_decl = codegen_emit_storage_values.append_typed_local_with_decl;
const append_typed_local = codegen_emit_storage_values.append_typed_local;
const infer_lambda_expr_return_type = codegen_emit_storage_values.infer_lambda_expr_return_type;
const clone_local_set = codegen_storage_layout.clone_local_set;
const callback_function_matches_shape = codegen_emit_storage_values.callback_function_matches_shape;
const callback_lambda_return_matches_shape = codegen_emit_storage_values.callback_lambda_return_matches_shape;
const find_callback_ref_func = codegen_storage_layout.find_callback_ref_func;
const lambda_explicit_types_match_shape = codegen_emit_storage_values.lambda_explicit_types_match_shape;
const type_base_name = codegen_emit_storage_values.type_base_name;
const value_enum_type_matches_import_alias = codegen_emit_storage_values.value_enum_type_matches_import_alias;
const find_value_enum_branch_value = codegen_emit_storage_values.find_value_enum_branch_value;
const value_enum_branch_value_in_line = codegen_emit_storage_values.value_enum_branch_value_in_line;
const value_enum_source_matches_import = codegen_emit_storage_values.value_enum_source_matches_import;
const managed_payload_elem_type_from_name = codegen_emit_storage_values.managed_payload_elem_type_from_name;
const abs_result_type = codegen_emit_storage_values.abs_result_type;
const infer_first_arg_type_or_default_s32 = codegen_emit_storage_values.infer_first_arg_type_or_default_s32;
const wasi_do_result_type = codegen_emit_storage_values.wasi_do_result_type;
const memory_load_result_type = codegen_emit_storage_values.memory_load_result_type;
const infer_path_get_call_type = codegen_emit_storage_values.infer_path_get_call_type;
const infer_managed_struct_expr_field_type = codegen_emit_storage_values.infer_managed_struct_expr_field_type;
const find_concrete_struct_field_type_no_alloc = codegen_emit_storage_values.find_concrete_struct_field_type_no_alloc;
const generic_type_arg_at = codegen_emit_storage_values.generic_type_arg_at;
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
    const struct_local = find_struct_local(locals.struct_locals.items, source_name);
    const target_name = if (struct_local) |local| local.name else resolved_local_name(locals.locals.items, source_name);
    const struct_ty = if (struct_local) |local|
        local.ty
    else if (try typed_struct_binding(allocator, tokens, start_idx, end_idx, ctx, &owned_types)) |binding|
        binding.ty
    else if (inferred_struct_binding(tokens, start_idx, end_idx, locals, ctx)) |binding|
        binding.ty
    else
        decl.name;
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    if (find_struct_layout(ctx.struct_layouts, struct_ty) != null and !is_struct_literal_rhs(tokens, eq_idx + 1, end_idx)) {
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
        if (!emitted_move_call and is_direct_managed_local_expr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try append_fmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }
    if (find_struct_layout(ctx.struct_layouts, struct_ty) == null) {
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
                try append_fmt(allocator, out, "    local.set ${s}.{s}\n", .{
                    target_name,
                    public_decl_name(decl.fields[field_idx].name),
                });
            }
            return;
        }
    }
    const open_brace = struct_literal_open_rhs(tokens, eq_idx + 1, end_idx) orelse return error.NoMatchingCall;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return error.NoMatchingCall;
    if (close_brace + 1 != end_idx) return error.NoMatchingCall;

    if (find_struct_layout(ctx.struct_layouts, struct_ty)) |layout| {
        try append_fmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
        try append_fmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
        try out.appendSlice(allocator, "    call $__arc_alloc\n");
        try append_fmt(allocator, out, "    local.set ${s}\n", .{target_name});
        try emit_managed_struct_fields(allocator, tokens, open_brace + 1, close_brace, target_name, locals, ctx, decl, struct_ty, layout, &owned_types, out);
        return;
    }

    for (decl.fields) |field| {
        const field_name = public_decl_name(field.name);
        const literal_field = find_struct_literal_field(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, &owned_types);
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
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trim_parens(tokens, eq_idx + 1, end_idx);
    const call_head = expr_call_head(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
    const result_struct = func.result_struct orelse return false;
    if (!std.mem.eql(u8, result_struct, struct_ty)) return false;
    if (func.results.len != decl.fields.len) return error.NoMatchingCall;
    for (decl.fields, 0..) |field, idx| {
        const field_ty = try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, &owned_types);
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
        const field_ty = try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, &owned_types);
        try emit_struct_field_local_set(allocator, tokens, tokens[start_idx].lexeme, public_decl_name(field.name), field_ty, locals, ctx, out);
    }
    return true;
}

pub fn emit_unmanaged_struct_error_union_return(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_start: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_struct: ?[]const u8, defer_ctx: ?*const DeferContext, out: *std.ArrayList(u8)) !bool {
    const error_name = unmanaged_struct_error_union_result(tokens, ctx, result_tys, result_struct) orelse return false;
    const struct_name = result_struct.?;
    const decl = find_struct_decl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (start_idx + 1 >= end_idx) return error.NoMatchingCall;

    const expr_start = start_idx + 1;
    const expr_end = end_idx;
    const range = trim_parens(tokens, expr_start, expr_end);

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
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
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

    if (find_struct_local(locals.struct_locals.items, name)) |struct_local| {
        if (std.mem.eql(u8, struct_local.ty, struct_name) and find_struct_layout(ctx.struct_layouts, struct_name) == null) {
            try emit_struct_fields_from_local(allocator, tokens, struct_local, decl, locals, ctx, false, out);
            try out.appendSlice(allocator, "    i32.const 0\n");
            return true;
        }
    }

    const is_error_branch = error_enum_branch_value(tokens, error_name, name) != null;
    const is_error_local = std.mem.eql(u8, find_local_type(locals.locals.items, name) orelse "", error_name);
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
        defer free_union_layout(allocator, layout);
        return try codegen_callbacks.emit_union_value(allocator, tokens, arg_start, arg_end, locals, ctx, layout, copy_managed, null, out);
    }
    if (is_tuple_type_name(param_ty)) {
        if (try emit_tuple_expr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out)) {
            return true;
        }
    }
    const range = trim_parens(tokens, arg_start, arg_end);
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        if (find_struct_local(locals.struct_locals.items, tokens[range.start].lexeme)) |struct_local| {
            if (std.mem.eql(u8, struct_local.ty, param_ty) and find_struct_layout(ctx.struct_layouts, param_ty) == null) {
                const decl = find_struct_decl(ctx.structs, param_ty) orelse return false;
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
    const decl = find_struct_decl(ctx.structs, expected_ty) orelse return false;
    const open_brace = struct_literal_open_rhs(tokens, start_idx, end_idx) orelse return false;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    if (find_struct_layout(ctx.struct_layouts, expected_ty)) |layout| {
        try append_fmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
        try append_fmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
        try out.appendSlice(allocator, "    call $__arc_alloc\n");
        try append_fmt(allocator, out, "    local.set ${s}\n", .{STRUCT_LITERAL_TMP_LOCAL});
        try emit_managed_struct_fields(allocator, tokens, open_brace + 1, close_brace, STRUCT_LITERAL_TMP_LOCAL, locals, ctx, decl, expected_ty, layout, &owned_types, out);
        try append_fmt(allocator, out, "    local.get ${s}\n", .{STRUCT_LITERAL_TMP_LOCAL});
        return true;
    }

    for (decl.fields) |field| {
        const field_name = public_decl_name(field.name);
        const literal_field = find_struct_literal_field(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substitute_struct_field_type(allocator, decl, expected_ty, field.ty, &owned_types);
        try emit_struct_field_value(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, false, out);
    }
    return true;
}

pub fn emit_struct_set_assignment(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, body_end: usize, allow_last_use_move: bool, locals: *const LocalSet, defer_ctx: ?*const DeferContext, ctx: CodegenContext, out: *std.ArrayList(u8)) !bool {
    if (start_idx + 6 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const struct_local = find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!tok_eq(tokens[start_idx + 1], "=")) return false;

    var name_idx = start_idx + 2;
    if (tok_eq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= end_idx) return false;
    }
    if (!std.mem.eql(u8, tokens[name_idx].lexeme, "set")) return false;
    if (name_idx + 1 >= end_idx or !tok_eq(tokens[name_idx + 1], "(")) return false;

    const open_paren = name_idx + 1;
    const args_start = open_paren + 1;
    const close_paren = find_matching_in_range(tokens, open_paren, "(", ")", end_idx) catch return false;
    if (close_paren + 1 != end_idx) return false;

    const first_end = find_arg_end(tokens, args_start, close_paren);
    if (first_end != args_start + 1 or !std.mem.eql(u8, tokens[args_start].lexeme, tokens[start_idx].lexeme)) return false;
    if (first_end >= close_paren or !tok_eq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, close_paren);
    if (field_end != field_start + 1 or !is_dot_ident(tokens[field_start].lexeme)) return false;
    if (field_end >= close_paren or !tok_eq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const field_name = public_decl_name(tokens[field_start].lexeme);
    const decl = find_struct_decl(ctx.structs, struct_local.ty) orelse return false;
    const field_ty = find_local_field_type(locals.locals.items, struct_local.name, field_name) orelse
        find_struct_field_type(decl, field_name) orelse return false;

    if (find_struct_layout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return false;
        try append_fmt(allocator, out, "    ;; arc-managed-struct-set name={s} field={s} offset={d}\n", .{
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
        try append_store_for_payload_type(allocator, out, field_ty);
        return true;
    }

    if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try append_fmt(allocator, out, "    local.set ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}

pub fn resolved_local_name(locals: []const Local, name: []const u8) []const u8 {
    return find_local_name(locals, name) orelse name;
}

fn type_args_close_idx(tokens: []const lexer.Token, open_angle: usize, end_idx: usize) ?usize {
    var depth: usize = 0;
    var j = open_angle;
    while (j < end_idx) : (j += 1) {
        if (tok_eq(tokens[j], "<")) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[j], ">")) continue;
        if (depth == 0) return null;
        depth -= 1;
        if (depth == 0) return j;
    }
    return null;
}

pub fn stmt_contains_struct_literal_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and tok_eq(tokens[i + 1], "{")) return true;
        if (tokens[i].kind == .ident and tok_eq(tokens[i + 1], "<")) {
            const close = type_args_close_idx(tokens, i + 1, end_idx) orelse continue;
            if (close + 1 < end_idx and tok_eq(tokens[close + 1], "{")) return true;
        }
        if (tok_eq(tokens[i], ".") and tok_eq(tokens[i + 1], "{")) return true;
    }
    return false;
}

pub fn emit_unmanaged_struct_return_local(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, result_tys: []const []const u8, result_struct: ?[]const u8, out: *std.ArrayList(u8)) !bool {
    const struct_name = result_struct orelse return false;
    if (is_tuple_type_name(struct_name)) return false;
    if (start_idx + 2 != end_idx) return false;
    if (tokens[start_idx + 1].kind != .ident) return false;
    const local_name = tokens[start_idx + 1].lexeme;
    const struct_local = find_struct_local(locals.struct_locals.items, local_name) orelse return false;
    if (!std.mem.eql(u8, struct_local.ty, struct_name)) return false;
    if (find_struct_layout(ctx.struct_layouts, struct_name) != null) return false;
    const decl = find_struct_decl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (decl.fields.len != result_tys.len) return error.NoMatchingCall;

    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return error.NoMatchingCall;
        try append_fmt(allocator, out, "    local.get ${s}.{s}\n", .{
            local_name,
            public_decl_name(field.name),
        });
    }
    return true;
}

pub fn emit_managed_struct_set_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, decl: StructDecl, struct_ty: []const u8, owned_types: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) CodegenError!bool {
    const layout = find_struct_layout(ctx.struct_layouts, struct_ty) orelse return false;
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "set")) return false;

    const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
    if (first_end != call_head.args_start + 1 or tokens[call_head.args_start].kind != .ident) return false;
    if (first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return false;
    const source_local = find_struct_local(locals.struct_locals.items, tokens[call_head.args_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, source_local.ty, struct_ty)) return false;

    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, call_head.args_end);
    if (field_end != field_start + 1 or !is_dot_ident(tokens[field_start].lexeme)) return false;
    if (field_end >= call_head.args_end or !tok_eq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const value_end = find_arg_end(tokens, value_start, call_head.args_end);
    if (value_end != call_head.args_end) return false;
    const target_field = public_decl_name(tokens[field_start].lexeme);

    try append_fmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
    try append_fmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try append_fmt(allocator, out, "    local.set ${s}\n", .{target_name});

    for (decl.fields) |field| {
        const field_name = public_decl_name(field.name);
        const field_ty = try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, owned_types);
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return false;
        try append_managed_struct_field_ptr(allocator, out, target_name, field_offset);
        if (std.mem.eql(u8, field_name, target_field)) {
            if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            if (is_managed_struct_field(layout, field_name) and is_direct_managed_local_expr(tokens, value_start, value_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try append_store_for_payload_type(allocator, out, field_ty);
            continue;
        }

        try append_managed_struct_field_ptr(allocator, out, source_local.name, field_offset);
        try append_load_for_payload_type(allocator, out, field_ty);
        if (is_managed_struct_field(layout, field_name)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try append_store_for_payload_type(allocator, out, field_ty);
    }
    return true;
}

pub fn emit_managed_struct_fields(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, local_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, decl: StructDecl, struct_ty: []const u8, layout: StructLayout, owned_types: *std.ArrayList([]const u8), out: *std.ArrayList(u8)) !void {
    for (decl.fields) |field| {
        const field_name = public_decl_name(field.name);
        const literal_field = find_struct_literal_field(tokens, start_idx, end_idx, field_name);
        const expr_tokens = if (literal_field) |_| tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_offset = struct_field_payload_offset(decl, field_name) orelse return error.NoMatchingCall;
        const field_ty = try substitute_struct_field_type(allocator, decl, struct_ty, field.ty, owned_types);

        try append_fmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try out.appendSlice(allocator, "    call $__arc_payload\n");
        try append_fmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        if (!try codegen_callbacks.emit_expr(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        if (is_managed_struct_field(layout, field_name) and is_direct_managed_local_expr(expr_tokens, expr_start, expr_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try append_store_for_payload_type(allocator, out, field_ty);
    }
}

pub fn emit_struct_set_expr(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected_ty: ?[]const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or !is_dot_ident(tokens[field_start].lexeme)) return false;
    if (field_end >= end_idx or !tok_eq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const value_end = find_arg_end(tokens, value_start, end_idx);
    if (value_end != end_idx) return false;

    const struct_local = find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const struct_ty = expected_ty orelse struct_local.ty;
    if (!std.mem.eql(u8, struct_local.ty, struct_ty)) return false;
    if (find_struct_layout(ctx.struct_layouts, struct_ty) != null) return false;

    const decl = find_struct_decl(ctx.structs, struct_ty) orelse return false;
    const target_field = public_decl_name(tokens[field_start].lexeme);
    for (decl.fields) |field| {
        const field_name = public_decl_name(field.name);
        const field_ty = find_local_field_type(locals.locals.items, struct_local.name, field_name) orelse
            find_struct_field_type(decl, field_name) orelse return false;
        if (std.mem.eql(u8, field_name, target_field)) {
            if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            continue;
        }
        try append_fmt(allocator, out, "    local.get ${s}.{s}\n", .{
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
    if (find_struct_layout(ctx.struct_layouts, struct_name) != null) return null;
    const decl = find_struct_decl(ctx.structs, struct_name) orelse return null;
    if (result_tys.len != decl.fields.len + 1) return null;
    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return null;
    }
    const error_name = result_tys[decl.fields.len];
    if (!is_error_like_type(tokens, error_name)) return null;
    return error_name;
}

pub const emit_release_managed_locals = gen_ownership.emitReleaseManagedLocals;
pub const emit_release_managed_locals_except = gen_ownership.emitReleaseManagedLocalsExcept;
pub const emit_release_managed_locals_except_many = gen_ownership.emitReleaseManagedLocalsExceptMany;
pub const emit_fallthrough_release_managed_locals = gen_ownership.emitFallthroughReleaseManagedLocals;
pub const emit_block_release_managed_locals = gen_ownership.emitBlockReleaseManagedLocals;
pub const has_managed_locals = gen_ownership.hasManagedLocals;
pub const managed_local_kind_for_type = gen_ownership.managedLocalKindForType;
pub const collect_managed_ownership_locals = gen_ownership.collectManagedOwnershipLocals;
pub const build_return_ownership_plan = gen_ownership.buildReturnOwnershipPlan;
pub const build_guard_return_ownership_plan = gen_ownership.buildGuardReturnOwnershipPlan;
pub const build_fallthrough_ownership_plan = gen_ownership.buildFallthroughOwnershipPlan;
pub const build_block_ownership_plan = gen_ownership.buildBlockOwnershipPlan;
pub const emit_ownership_release_plan = gen_ownership.emitOwnershipReleasePlan;
pub const body_ends_with_plain_return = gen_ownership.bodyEndsWithPlainReturn;
pub const body_can_reach_end = gen_ownership.bodyCanReachEnd;
pub const stmt_can_reach_end = gen_ownership.stmtCanReachEnd;
pub const if_stmt_can_reach_end = gen_ownership.ifStmtCanReachEnd;
pub const loop_stmt_can_reach_end = gen_ownership.loopStmtCanReachEnd;
