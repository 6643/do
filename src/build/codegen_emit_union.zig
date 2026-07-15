//! Union value / binding emit.
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
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const gen_import = @import("gen_import.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
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
const codegen_emit_storage_operations = @import("codegen_emit_storage_operations.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_emit_struct = @import("codegen_emit_struct.zig");
const codegen_emit_struct_fields = @import("codegen_emit_struct_fields.zig");
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
const is_storage_agg_literal_expr = codegen_emit_storage_values.isStorageAggLiteralExpr;
const count_agg_literal_items = codegen_emit_storage_values.count_agg_literal_items;
const emit_storage_payload_ptr = codegen_emit_storage_values.emit_storage_payload_ptr;
const emit_storage_len_ptr_with_indent = codegen_emit_storage_values.emitStorageLenPtrWithIndent;
const emit_storage_cap_ptr = codegen_emit_storage_values.emitStorageCapPtr;
const emit_storage_cap_ptr_with_indent = codegen_emit_storage_values.emitStorageCapPtrWithIndent;
const emit_storage_payload_ptr_with_indent = codegen_emit_storage_values.emit_storage_payload_ptr_with_indent;
const emit_tuple_local_set = codegen_emit_storage_values.emit_tuple_local_set;
const emit_tuple_local_get = codegen_emit_storage_values.emit_tuple_local_get;
const emit_tuple_get_binding = codegen_emit_storage_values.emit_tuple_get_binding;
const emit_storage_content_comparison_call = codegen_emit_storage_values.emit_storage_content_comparison_call;
const emit_managed_payload_storage_content_comparison_call = codegen_emit_storage_values.emit_managed_payload_storage_content_comparison_call;
const infer_storage_content_comparison_type = codegen_storage_layout.infer_storage_content_comparison_type;
const storage_content_arg_compatible = codegen_storage_layout.storage_content_arg_compatible;
const is_managed_payload_comparable_type = codegen_storage_layout.is_managed_payload_comparable_type;
const emit_storage_ptr_len_host_arg = codegen_emit_storage_values.emit_storage_ptr_len_host_arg;
const emit_tuple_expr = codegen_emit_storage_values.emit_tuple_expr;
const storage_binding_elem_type = codegen_storage_layout.storage_binding_elem_type;
const managed_payload_binding = codegen_storage_layout.managed_payload_binding;
const parse_storage_type = codegen_storage_layout.parse_storage_type;
const emit_storage_bounds_check = codegen_emit_storage_operations.emit_storage_bounds_check;
const emit_storage_write_expr = codegen_emit_storage_operations.emit_storage_write_expr;
const emit_storage_set_expr = codegen_emit_storage_operations.emit_storage_set_expr;
const emit_storage_put_call = codegen_emit_storage_operations.emit_storage_put_call;
const emit_storage_put_expr = codegen_emit_storage_operations.emit_storage_put_expr;
const emit_storage_put_spread_call = codegen_emit_storage_operations.emit_storage_put_spread_call;
const emit_storage_set_scalar_call = codegen_emit_storage_operations.emit_storage_set_scalar_call;
const emit_storage_put_spread_scalar_element = codegen_emit_storage_operations.emit_storage_put_spread_scalar_element;
const emit_storage_put_scalar_call = codegen_emit_storage_operations.emit_storage_put_scalar_call;
const emit_storage_clone_current_len = codegen_emit_storage_operations.emit_storage_clone_current_len;
const emit_storage_clone_current_len_for_elem = codegen_emit_storage_operations.emit_storage_clone_current_len_for_elem;
const emit_storage_clone_managed_current_len = codegen_emit_storage_operations.emit_storage_clone_managed_current_len;
const emit_storage_clone_managed_with_len_local = codegen_emit_storage_operations.emit_storage_clone_managed_with_len_local;
const emit_storage_inc_copied_managed_elements = codegen_emit_storage_operations.emit_storage_inc_copied_managed_elements;
const emit_storage_clone_with_len_local = codegen_emit_storage_operations.emit_storage_clone_with_len_local;
const emit_storage_clone_with_len_local_for_elem = codegen_emit_storage_operations.emit_storage_clone_with_len_local_for_elem;
const emit_storage_clone_with_len_local_typed = codegen_emit_storage_operations.emit_storage_clone_with_len_local_typed;
const emit_storage_inc_copied_pack_elements = codegen_emit_storage_values.emit_storage_inc_copied_pack_elements;
const emit_storage_element_ptr_from_local = codegen_emit_storage_operations.emit_storage_element_ptr_from_local;
const emit_storage_element_ptr_from_local_with_indent = codegen_emit_storage_operations.emit_storage_element_ptr_from_local_with_indent;
const emit_storage_alias_protect = codegen_emit_storage_operations.emit_storage_alias_protect;
const emit_storage_alias_release = codegen_emit_storage_operations.emit_storage_alias_release;
const emit_empty_storage_u8_value = codegen_emit_storage_values.emit_empty_storage_u8_value;
const emit_empty_storage_for_elem_type = codegen_emit_storage_values.emit_empty_storage_for_elem_type;
const storage_element_byte_width_for_type = codegen_storage_layout.storage_element_byte_width_for_type;
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
const is_direct_managed_local_expr = codegen_emit_storage_values.isDirectManagedLocalExpr;
const storage_pack_layout_for_elem = codegen_storage_layout.storage_pack_layout_for_elem;
const tuple_element_pack_offset_with_structs = codegen_emit_storage_values.tuple_element_pack_offset_with_structs;
const tuple_field_path_type = codegen_storage_layout.tuple_field_path_type;
const find_struct_literal_field = codegen_emit_storage_values.find_struct_literal_field;
const substitute_struct_field_type = codegen_storage_layout.substitute_struct_field_type;
const is_struct_literal_rhs = codegen_emit_storage_values.is_struct_literal_rhs;
const emit_replace_storage_put_source_tmp = codegen_emit_storage_operations.emit_replace_storage_put_source_tmp;
const direct_managed_local_expr_name = codegen_emit_storage_values.directManagedLocalExprName;
const emit_overwrite_release_managed_local = codegen_emit_storage_operations.emit_overwrite_release_managed_local;
const find_local_field_type = codegen_storage_layout.find_local_field_type;
const tuple_get_element_info = codegen_emit_storage_values.tuple_get_element_info;
const find_func_decl_for_call_head = codegen_storage_layout.find_func_decl_for_call_head;
const infer_expr_type = codegen_storage_layout.infer_expr_type;
const find_struct_literal_field_end = codegen_emit_storage_values.find_struct_literal_field_end;
const find_struct_field_type = codegen_storage_layout.find_struct_field_type;
const local_field_name_matches = codegen_emit_storage_values.localFieldNameMatches;
const direct_managed_last_use_move_source = codegen_emit_storage_values.direct_managed_last_use_move_source;
const struct_literal_open_rhs = codegen_emit_storage_values.structLiteralOpenRhs;
const union_payload_local_name_from_locals = codegen_emit_storage_values.unionPayloadLocalNameFromLocals;
const substitute_generic_type = codegen_emit_storage_values.substituteGenericType;
const is_union_payload_local_name = codegen_emit_storage_values.isUnionPayloadLocalName;
const find_callback_call_arg = codegen_emit_storage_values.findCallbackCallArg;
const append_tuple_local_fields_borrowed = codegen_emit_storage_values.appendTupleLocalFieldsBorrowed;
const find_func_decl_for_call = codegen_emit_storage_values.findFuncDeclForCall;
const find_local_name = codegen_emit_storage_values.findLocalName;
const emit_storage_set_call = codegen_emit_storage_operations.emit_storage_set_call;
const emit_storage_put_one_call = codegen_emit_storage_operations.emit_storage_put_one_call;
const call_explicit_type_args_match_bindings = codegen_emit_storage_values.callExplicitTypeArgsMatchBindings;
const call_args_match_func_params = codegen_emit_storage_values.callArgsMatchFuncParams;
const has_registered_defer_stmt = codegen_emit_storage_values.has_registered_defer_stmt;
const append_borrowed_local_field = codegen_emit_storage_values.appendBorrowedLocalField;
const token_range_uses_ident = codegen_emit_storage_values.token_range_uses_ident;
const should_infer_bool_special_call = codegen_emit_storage_values.shouldInferBoolSpecialCall;
const is_defer_stmt = codegen_emit_storage_values.is_defer_stmt;
const call_arg_matches_callback_shape = codegen_emit_storage_values.callArgMatchesCallbackShape;
const emit_storage_set_managed_call = codegen_emit_storage_operations.emit_storage_set_managed_call;
const emit_storage_put_managed_call = codegen_emit_storage_operations.emit_storage_put_managed_call;
const emit_managed_storage_value = codegen_emit_storage_values.emitManagedStorageValue;
const infer_scalar_as_call_type = codegen_emit_storage_values.inferScalarAsCallType;
const find_callback_binding = codegen_storage_layout.find_callback_binding;
const scalar_as_target_type = codegen_emit_storage_values.scalarAsTargetType;
const call_arg_matches_concrete_callback_binding = codegen_emit_storage_values.callArgMatchesConcreteCallbackBinding;
const is_scalar_as_target_type_name = codegen_emit_storage_values.isScalarAsTargetTypeName;
const infer_set_call_type = codegen_storage_layout.infer_set_call_type;
const callback_bindings_have_same_shape = codegen_storage_layout.callback_bindings_have_same_shape;
const call_arg_matches_param = codegen_storage_layout.call_arg_matches_param;
const infer_put_call_type = codegen_storage_layout.infer_put_call_type;
const call_args_match_variadic_tail = codegen_storage_layout.call_args_match_variadic_tail;
const call_arg_matches_union_param = codegen_emit_storage_values.callArgMatchesUnionParam;
const union_type_name_has_branch = codegen_emit_storage_values.unionTypeNameHasBranch;
const infer_field_get_call_type = codegen_storage_layout.infer_field_get_call_type;
const func_variadic_elem_type = codegen_storage_layout.func_variadic_elem_type;
const infer_field_set_call_type = codegen_storage_layout.infer_field_set_call_type;
const find_field_meta_local = codegen_emit_storage_values.findFieldMetaLocal;
const struct_literal_expr_matches_type = codegen_emit_storage_values.structLiteralExprMatchesType;
const infer_get_call_type = codegen_storage_layout.infer_get_call_type;
const lambda_expr_shape = codegen_storage_layout.lambda_expr_shape;
const lambda_param_count = codegen_emit_storage_values.lambdaParamCount;
const callback_binding_has_same_concrete_arg = codegen_storage_layout.callback_binding_has_same_concrete_arg;
const value_enum_branch_value = codegen_emit_storage_values.valueEnumBranchValue;
const infer_tuple_field_path_get_type = codegen_storage_layout.infer_tuple_field_path_get_type;
const append_managed_struct_field_meta_local = codegen_emit_storage_values.appendManagedStructFieldMetaLocal;
const field_from_meta = codegen_emit_storage_values.fieldFromMeta;
const find_struct_field = codegen_storage_layout.find_struct_field;
const union_local_default_payload_type = codegen_storage_layout.union_local_default_payload_type;
const union_local_default_struct_payload = codegen_emit_storage_values.unionLocalDefaultStructPayload;
const find_narrowed_union_type = codegen_storage_layout.find_narrowed_union_type;
const is_dot_ident = codegen_emit_storage_values.isDotIdent;
const is_arrow_at = codegen_emit_storage_values.isArrowAt;
const lambda_body_start = codegen_emit_storage_values.lambdaBodyStart;
const lambda_param_type_name = codegen_storage_layout.lambda_param_type_name;
const lambda_explicit_return_type = codegen_storage_layout.lambda_explicit_return_type;
const append_typed_local_with_decl = codegen_emit_storage_values.appendTypedLocalWithDecl;
const append_typed_local = codegen_emit_storage_values.appendTypedLocal;
const infer_lambda_expr_return_type = codegen_storage_layout.infer_lambda_expr_return_type;
const clone_local_set = codegen_storage_layout.clone_local_set;
const callback_function_matches_shape = codegen_emit_storage_values.callbackFunctionMatchesShape;
const callback_lambda_return_matches_shape = codegen_emit_storage_values.callbackLambdaReturnMatchesShape;
const find_callback_ref_func = codegen_storage_layout.find_callback_ref_func;
const lambda_explicit_types_match_shape = codegen_emit_storage_values.lambdaExplicitTypesMatchShape;
const type_base_name = codegen_emit_storage_values.typeBaseName;
const value_enum_type_matches_import_alias = codegen_emit_storage_values.valueEnumTypeMatchesImportAlias;
const find_value_enum_branch_value = codegen_emit_storage_values.findValueEnumBranchValue;
const value_enum_branch_value_in_line = codegen_emit_storage_values.valueEnumBranchValueInLine;
const value_enum_source_matches_import = codegen_emit_storage_values.valueEnumSourceMatchesImport;
const managed_payload_elem_type_from_name = codegen_storage_layout.managed_payload_elem_type_from_name;
const abs_result_type = codegen_emit_storage_values.absResultType;
const infer_first_arg_type_or_default_s32 = codegen_emit_storage_values.inferFirstArgTypeOrDefaultS32;
const wasi_do_result_type = codegen_emit_storage_values.wasiDoResultType;
const memory_load_result_type = codegen_emit_storage_values.memoryLoadResultType;
const infer_path_get_call_type = codegen_emit_storage_values.inferPathGetCallType;
const infer_managed_struct_expr_field_type = codegen_emit_storage_values.inferManagedStructExprFieldType;
const find_concrete_struct_field_type_no_alloc = codegen_emit_storage_values.findConcreteStructFieldTypeNoAlloc;
const generic_type_arg_at = codegen_emit_storage_values.genericTypeArgAt;
const emit_managed_handle_call_expr_with_move_context = codegen_emit_storage_values.emit_managed_handle_call_expr_with_move_context;
const emit_storage_handle_binding_expr = codegen_emit_storage_values.emit_storage_handle_binding_expr;
const emit_tuple_call_binding = codegen_emit_storage_values.emit_tuple_call_binding;
const emit_field_reflection_body = codegen_emit_struct_fields.emit_field_reflection_body;
const emit_field_reflection_loop_block = codegen_emit_struct_fields.emit_field_reflection_loop_block;
const emit_managed_struct_field_set = codegen_emit_struct_fields.emit_managed_struct_field_set;
const emit_struct_binding = codegen_emit_struct.emit_struct_binding;
const emit_struct_field_value = codegen_emit_struct_fields.emit_struct_field_value;
const emit_unmanaged_struct_call_binding = codegen_emit_struct.emit_unmanaged_struct_call_binding;
const emit_unmanaged_struct_error_union_return = codegen_emit_struct.emit_unmanaged_struct_error_union_return;
const emit_user_func_arg = codegen_emit_struct.emit_user_func_arg;
const emit_struct_field_meta_set_assignment = codegen_emit_struct_fields.emit_struct_field_meta_set_assignment;
const emit_struct_literal_expr = codegen_emit_struct.emit_struct_literal_expr;
const emit_struct_set_assignment = codegen_emit_struct.emit_struct_set_assignment;
const field_static_values_equal = codegen_emit_struct_fields.field_static_values_equal;
const field_reflection_local_visible = codegen_emit_struct_fields.field_reflection_local_visible;
const append_union_payload_local_get = codegen_emit_struct.appendUnionPayloadLocalGet;
const resolved_local_name = codegen_emit_struct.resolved_local_name;
const append_union_tag_local_get = codegen_emit_struct.appendUnionTagLocalGet;
const append_union_tag_local_set = codegen_emit_struct.appendUnionTagLocalSet;
const is_managed_struct_field = codegen_emit_struct.isManagedStructField;
const struct_local_source_name = codegen_emit_struct.structLocalSourceName;
const stmt_contains_struct_literal_expr = codegen_emit_struct.stmt_contains_struct_literal_expr;
const field_reflection_local_name_prefix = codegen_emit_struct_fields.field_reflection_local_name_prefix;
const emit_unmanaged_struct_return_local = codegen_emit_struct.emit_unmanaged_struct_return_local;
const emit_struct_field_local_get = codegen_emit_struct_fields.emit_struct_field_local_get;
const emit_struct_field_local_set = codegen_emit_struct_fields.emit_struct_field_local_set;
const emit_struct_fields_from_local = codegen_emit_struct_fields.emit_struct_fields_from_local;
const emit_managed_struct_set_binding = codegen_emit_struct.emit_managed_struct_set_binding;
const emit_managed_struct_fields = codegen_emit_struct.emit_managed_struct_fields;
const emit_managed_struct_clone_with_field_set = codegen_emit_struct.emitManagedStructCloneWithFieldSet;
const append_managed_struct_field_ptr = codegen_emit_struct_fields.append_managed_struct_field_ptr;
const field_reflection_if_parts = codegen_emit_struct_fields.field_reflection_if_parts;
const field_static_bool_expr = codegen_emit_struct_fields.field_static_bool_expr;
const field_static_value = codegen_emit_struct_fields.field_static_value;
const field_visible_from_tokens = codegen_emit_struct_fields.field_visible_from_tokens;
const is_private_field_name = codegen_emit_struct_fields.is_private_field_name;
const typed_struct_binding = codegen_emit_struct.typedStructBinding;
const inferred_struct_binding = codegen_emit_struct.inferredStructBinding;
const emit_managed_struct_expr_field_get = codegen_emit_struct_fields.emit_managed_struct_expr_field_get;
const emit_field_reflection_intrinsic = codegen_emit_struct_fields.emit_field_reflection_intrinsic;
const emit_field_get_call = codegen_emit_struct_fields.emit_field_get_call;
const emit_unmanaged_struct_field_get = codegen_emit_struct_fields.emit_unmanaged_struct_field_get;
const emit_struct_set_expr = codegen_emit_struct.emit_struct_set_expr;
const borrowed_field_meta_local_set = codegen_emit_struct_fields.borrowed_field_meta_local_set;
const single_field_meta_arg = codegen_emit_struct_fields.single_field_meta_arg;
const field_get_last_use_move_source = codegen_emit_struct_fields.field_get_last_use_move_source;
const unmanaged_struct_error_union_result = codegen_emit_struct.unmanaged_struct_error_union_result;
const fresh_struct_literal_binding_stmt_end = codegen_emit_struct.freshStructLiteralBindingStmtEnd;
const emit_zero_value_for_type = codegen_emit_struct.emitZeroValueForType;
const collect_field_reflection_body_locals = codegen_emit_struct_fields.collect_field_reflection_body_locals;
const append_union_payload_local_set = codegen_emit_struct.appendUnionPayloadLocalSet;
const apply_guard_return_nil_narrowing = codegen_emit_struct.applyGuardReturnNilNarrowing;
const apply_guard_return_is_narrowing = codegen_emit_struct.applyGuardReturnIsNarrowing;
const apply_guard_loop_control_narrowing = codegen_emit_struct_fields.apply_guard_loop_control_narrowing;
const nil_comparison_narrowing = codegen_emit_struct.nilComparisonNarrowing;
const is_comparison_narrowing = codegen_emit_struct.isComparisonNarrowing;
const single_ident_expr = codegen_emit_struct.singleIdentExpr;
const single_nil_expr = codegen_emit_struct.singleNilExpr;
const union_local_single_non_nil_payload_type = codegen_emit_struct.unionLocalSingleNonNilPayloadType;
const union_local_single_remaining_payload_type = codegen_emit_struct.unionLocalSingleRemainingPayloadType;
const trim_trailing_comma = codegen_emit_struct.trimTrailingComma;
const apply_collect_guard_return_narrowing = codegen_emit_struct_fields.apply_collect_guard_return_narrowing;
const merge_return_cleanup_locals = codegen_emit_struct.mergeReturnCleanupLocals;
const field_reflection_scoped_cleanup_local_set = codegen_emit_struct_fields.field_reflection_scoped_cleanup_local_set;

pub const emit_wasi_result_read_values = codegen_emit_wasi.emit_wasi_result_read_values;
pub const emit_wasi_result_list_u8_values = codegen_emit_wasi.emit_wasi_result_list_u8_values;
pub const emit_wasi_result_descriptor_values = codegen_emit_wasi.emit_wasi_result_descriptor_values;
pub const emit_wasi_result_filesize_values = codegen_emit_wasi.emit_wasi_result_filesize_values;
pub const emit_wasi_list_u8_arg = codegen_emit_wasi.emit_wasi_list_u8_arg;
pub const wasm_type = codegen_emit_wasi.wasm_type;
pub const value_enum_carrier = codegen_emit_wasi.value_enum_carrier;
pub const codegen_scalar_type = codegen_emit_wasi.codegen_scalar_type;
// re-export codegen_emit_struct

pub fn emit_union_return(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, layout: UnionLayout, move_names: *std.ArrayList([]const u8), defer_ctx: ?*const DeferContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (start_idx + 1 >= end_idx) return error.NoMatchingCall;
    const expr_start = start_idx + 1;
    const expr_end = end_idx;
    try collect_union_return_move_names(allocator, tokens, expr_start, expr_end, locals, ctx, layout, move_names);
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = end_idx,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    };
    return try emit_union_value(allocator, tokens, expr_start, expr_end, locals, ctx, layout, false, &move_ctx, out);
}

fn emit_union_value_from_user_func(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
    const func_union = func.result_union orelse return false;
    if (!union_layouts_abi_compatible(ctx, func_union, layout)) return false;
    return try codegen_callbacks.emit_user_func_call_with_move_context(
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

fn emit_union_value_from_wasi(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    // Thin `return host_...(…)` / expr-position host → exclusive union.
    const wasi_import = find_wasi_host_import_for_tokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    return try emit_wasi_unit_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_descriptor_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_filesize_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_list_u8_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_read_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, layout, out, codegen_callbacks.emit_expr);
}

fn emit_union_value_from_call(
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
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (call_head.is_intrinsic) {
        if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "field_get")) return false;
        return try emit_union_field_get_value(
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
    if (try emit_union_value_from_user_func(allocator, tokens, call_head, locals, ctx, layout, move_ctx, out)) return true;
    return emit_union_value_from_wasi(allocator, tokens, call_head, locals, ctx, layout, out);
}

fn emit_union_value_from_local(
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
    const union_local = find_union_local(locals.union_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!union_layouts_equal(union_local.layout, layout)) return false;

    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try append_union_payload_local_get(allocator, out, union_local.name, idx);
        if (copy_managed and is_managed_local_type(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try append_union_tag_local_get(allocator, out, union_local.name);
    return true;
}

pub fn emit_union_value(
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
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (try emit_union_value_from_call(allocator, tokens, range, locals, ctx, layout, copy_managed, move_ctx, out)) return true;

    if (range.end == range.start + 1 and tok_eq(tokens[range.start], "nil")) {
        for (layout.payload_tys) |payload_ty| {
            try emit_zero_value_for_type(allocator, ctx, out, payload_ty);
        }
        try out.appendSlice(allocator, "    i32.const 0\n");
        return true;
    }

    if (try emit_union_value_from_local(allocator, tokens, range, locals, ctx, layout, copy_managed, out)) return true;

    for (layout.branches) |branch| {
        // Flat unions reserve tag 0 for nil; payload enums use case-order tags including 0.
        if (branch.tag == 0 and std.mem.eql(u8, branch.ty, "nil")) continue;
        if (try emit_union_branch_value(allocator, tokens, range.start, range.end, locals, ctx, layout, branch, copy_managed, out)) {
            return true;
        }
    }
    return false;
}

pub fn emit_union_field_get_value(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, layout: UnionLayout, copy_managed: bool, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tok_eq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = find_arg_end(tokens, field_start, end_idx);
    if (field_end != end_idx) return false;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;

    const struct_local = find_struct_local(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const meta = find_field_meta_local(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, type_base_name(struct_local.ty), meta.struct_name)) return false;
    const field = field_from_meta(ctx, meta) orelse return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const field_layout = (try parse_type_union_layout_from_name(allocator, tokens, field.ty, ctx.structs, ctx.struct_layouts, &owned_types)) orelse return false;
    defer free_union_layout(allocator, field_layout);
    if (!union_layouts_equal(field_layout, layout)) return false;

    const field_name = public_decl_name(field.name);
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ struct_local.name, field_name });
    defer allocator.free(union_local_name);
    const union_local = find_union_local(locals.union_locals.items, union_local_name) orelse return false;
    if (!union_layouts_equal(union_local.layout, layout)) return false;

    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try append_union_payload_local_get(allocator, out, union_local.name, idx);
        if (copy_managed and is_managed_local_type(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try append_union_tag_local_get(allocator, out, union_local.name);
    return true;
}

pub fn emit_union_branch_value(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, layout: UnionLayout, branch: UnionBranch, copy_managed: bool, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trim_parens(tokens, start_idx, end_idx);

    // Payload-enum unit case: bare case name `Quit`.
    if (branch.payload_len == 0) {
        if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
            if (!std.mem.eql(u8, public_decl_name(tokens[range.start].lexeme), branch.ty)) return false;
            for (layout.payload_tys) |payload_ty| {
                try emit_zero_value_for_type(allocator, ctx, out, payload_ty);
            }
            try append_fmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
            return true;
        }
        return false;
    }

    // Payload-enum ctor: `Text(expr)` where Text is the case name.
    if (try emit_payload_enum_ctor_branch(
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
    if (!try emit_union_branch_payload(allocator, tokens, start_idx, end_idx, locals, ctx, branch, copy_managed, &branch_payload)) {
        return false;
    }
    try write_union_branch_slots(allocator, out, ctx, layout, branch, branch_payload.items);
    return true;
}

fn write_union_branch_slots(
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
            try emit_zero_value_for_type(allocator, ctx, out, payload_ty);
        }
    }
    try append_fmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
}

fn emit_payload_enum_ctor_branch(
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
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    if (tokens[call_head.name_idx].kind != .ident) return false;
    if (!std.mem.eql(u8, public_decl_name(tokens[call_head.name_idx].lexeme), branch.ty)) return false;

    const payload_ty = branch.payload_type orelse branch.ty;
    var branch_payload = std.ArrayList(u8).empty;
    defer branch_payload.deinit(allocator);
    if (!try codegen_callbacks.emit_expr(
        allocator,
        tokens,
        call_head.args_start,
        call_head.args_end,
        locals,
        ctx,
        payload_ty,
        &branch_payload,
    )) return false;

    if (copy_managed and is_managed_local_type(payload_ty, ctx) and
        is_direct_managed_local_expr(tokens, call_head.args_start, call_head.args_end, locals, ctx))
    {
        try branch_payload.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try write_union_branch_slots(allocator, out, ctx, layout, branch, branch_payload.items);
    return true;
}

/// Unmanaged pure-scalar struct local → expand field locals onto the operand stack.
fn emit_unmanaged_struct_local_as_payload(
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
    const struct_local = find_struct_local(locals.struct_locals.items, tokens[range_start].lexeme) orelse return null;
    if (!std.mem.eql(u8, struct_local.ty, emit_ty)) return null;
    if (find_struct_layout(ctx.struct_layouts, emit_ty) != null) return null;
    const decl = find_struct_decl(ctx.structs, emit_ty) orelse return false;
    for (decl.fields) |field| {
        try append_fmt(allocator, out, "    local.get ${s}.{s}\n", .{ struct_local.name, public_decl_name(field.name) });
    }
    return true;
}

pub fn emit_union_branch_payload(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, branch: UnionBranch, copy_managed: bool, out: *std.ArrayList(u8)) CodegenError!bool {
    if (branch.payload_len == 0) return false;
    const range = trim_parens(tokens, start_idx, end_idx);
    // Payload-enum cases: emit against payload_type when set (case name ≠ payload type).
    const emit_ty = branch.payload_type orelse branch.ty;

    if (try emit_unmanaged_struct_local_as_payload(allocator, tokens, range.start, range.end, locals, ctx, emit_ty, out)) |handled| {
        return handled;
    }

    if (!try codegen_callbacks.emit_expr(allocator, tokens, range.start, range.end, locals, ctx, emit_ty, out)) return false;
    if (copy_managed and is_managed_local_type(emit_ty, ctx) and is_direct_managed_local_expr(tokens, range.start, range.end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}

pub fn union_layouts_abi_compatible(ctx: CodegenContext, a: UnionLayout, b: UnionLayout) bool {
    if (a.branches.len != b.branches.len) return false;
    if (a.payload_tys.len != b.payload_tys.len) return false;
    for (a.payload_tys, 0..) |ty, idx| {
        if (!std.mem.eql(u8, codegen_wasm_type(ctx, ty), codegen_wasm_type(ctx, b.payload_tys[idx]))) return false;
    }
    for (a.branches, 0..) |branch, idx| {
        const other = b.branches[idx];
        if (branch.tag != other.tag) return false;
        if (branch.payload_start != other.payload_start) return false;
        if (branch.payload_len != other.payload_len) return false;
    }
    return true;
}

pub fn clone_union_layout_substituted(allocator: std.mem.Allocator, tokens: []const lexer.Token, structs: []const StructDecl, struct_layouts: []const StructLayout, layout: UnionLayout, bindings: []const GenericTypeBinding, owned_types: *std.ArrayList([]const u8)) !UnionLayout {
    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);
    var source_ty = std.ArrayList(u8).empty;
    errdefer source_ty.deinit(allocator);

    for (layout.branches, 0..) |branch, idx| {
        if (idx != 0) try source_ty.append(allocator, '|');
        const branch_ty = substitute_generic_type(branch.ty, bindings);
        try source_ty.appendSlice(allocator, branch_ty);

        const payload_start = payload_tys.items.len;
        if (branch.tag != 0) {
            try append_union_branch_payload_types(allocator, tokens, branch_ty, structs, struct_layouts, &payload_tys);
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
pub fn build_payload_enum_union_layout(allocator: std.mem.Allocator, decl: PayloadEnumDecl, tokens: []const lexer.Token, structs: []const StructDecl, struct_layouts: []const StructLayout, owned_types: *std.ArrayList([]const u8)) !UnionLayout {
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
            try append_union_branch_payload_types(allocator, tokens, pty, structs, struct_layouts, &tmp);
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
            try append_union_branch_payload_types(allocator, tokens, case.payload_ty.?, structs, struct_layouts, &tmp);
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

pub fn find_union_branch_by_compatible_type(layout: UnionLayout, ty: []const u8) ?UnionBranch {
    for (layout.branches) |branch| {
        if (codegen_types_compatible(branch.ty, ty)) return branch;
    }
    return null;
}

pub fn emit_union_struct_payload_for_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, name: []const u8, ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, copy_managed: bool, out: *std.ArrayList(u8)) CodegenError!bool {
    if (find_narrowed_union_type(locals.narrowed_union_locals.items, name)) |narrowed_ty| {
        if (!std.mem.eql(u8, narrowed_ty, ty)) return false;
    } else {
        return false;
    }
    const union_local = find_union_local(locals.union_locals.items, name) orelse return false;
    const payload = union_local_default_struct_payload(tokens, ctx, union_local) orelse return false;
    if (!std.mem.eql(u8, payload.decl.name, ty)) return false;

    if (payload.branch.payload_len == 1) {
        if (find_struct_layout(ctx.struct_layouts, payload.decl.name) != null) {
            try append_union_payload_local_get(allocator, out, union_local.name, payload.branch.payload_start);
            if (copy_managed) try out.appendSlice(allocator, "    call $__arc_inc\n");
            return true;
        }
    }

    var idx = payload.branch.payload_start;
    for (payload.decl.fields) |field| {
        try append_union_payload_local_get(allocator, out, union_local.name, idx);
        if (copy_managed and is_managed_local_type(field.ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        idx += 1;
    }
    return true;
}

pub fn emit_union_is_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end != args_start + 1 or tokens[args_start].kind != .ident) return false;
    if (first_end >= args_end or !tok_eq(tokens[first_end], ",")) return false;
    const union_local = find_union_local(locals.union_locals.items, tokens[args_start].lexeme) orelse return false;
    const type_start = first_end + 1;
    const type_end = args_end;

    var tags = std.ArrayList(usize).empty;
    defer tags.deinit(allocator);
    try collect_union_is_tags(allocator, tokens, type_start, type_end, ctx, union_local.layout, &tags);
    if (tags.items.len == 0) return false;

    for (tags.items, 0..) |tag, idx| {
        try append_union_tag_local_get(allocator, out, union_local.name);
        try append_fmt(allocator, out, "    i32.const {d}\n", .{tag});
        try out.appendSlice(allocator, "    i32.eq\n");
        if (idx != 0) try out.appendSlice(allocator, "    i32.or\n");
    }
    return true;
}

pub fn collect_union_is_tags(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, layout: UnionLayout, out: *std.ArrayList(usize)) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    var branch_start = start_idx;
    while (branch_start < end_idx) {
        if (tok_eq(tokens[branch_start], "|")) {
            branch_start += 1;
            continue;
        }
        const branch_end = find_top_level_token(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start) return error.NoMatchingCall;
        if (branch_end == branch_start + 1 and tok_eq(tokens[branch_start], "nil")) return error.NoMatchingCall;
        const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, branch_start, branch_end, &owned_types)) orelse return error.NoMatchingCall;
        if (parsed_ty.next_idx != branch_end) return error.NoMatchingCall;
        const branch = find_union_branch_by_type(layout, parsed_ty.ty) orelse return error.NoMatchingCall;
        if (branch.tag == 0 and std.mem.eql(u8, branch.ty, "nil")) return error.NoMatchingCall;
        try out.append(allocator, branch.tag);
        branch_start = branch_end;
        if (branch_start < end_idx and tok_eq(tokens[branch_start], "|")) branch_start += 1;
    }

    _ = ctx;
}

pub fn emit_union_nil_comparison(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, move_ctx: ?*const CallLastUseMoveContext, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tok_eq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = union_local_single_ident(tokens, args_start, first_end, locals);
    const second_union = union_local_single_ident(tokens, second_start, second_end, locals);
    const first_nil = first_end == args_start + 1 and tok_eq(tokens[args_start], "nil");
    const second_nil = second_end == second_start + 1 and tok_eq(tokens[second_start], "nil");

    if (first_union != null and second_nil) {
        try append_union_tag_local_get(allocator, out, first_union.?.name);
    } else if (second_union != null and first_nil) {
        try append_union_tag_local_get(allocator, out, second_union.?.name);
    } else if (second_nil) {
        if (!try emit_union_expr_tag_and_discard_payload(allocator, tokens, args_start, first_end, move_ctx, locals, ctx, out)) {
            return false;
        }
    } else if (first_nil) {
        if (!try emit_union_expr_tag_and_discard_payload(allocator, tokens, second_start, second_end, move_ctx, locals, ctx, out)) {
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

pub fn emit_union_expr_tag_and_discard_payload(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, move_ctx: ?*const CallLastUseMoveContext, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
    const layout = func.result_union orelse return false;
    if (!try codegen_callbacks.emit_user_func_call_with_move_context(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, move_ctx, out)) {
        return false;
    }
    try append_fmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    var idx = layout.payload_tys.len;
    while (idx > 0) {
        idx -= 1;
        if (is_managed_local_type(layout.payload_tys[idx], ctx)) {
            try out.appendSlice(allocator, "    call $__arc_dec\n");
        } else {
            try out.appendSlice(allocator, "    drop\n");
        }
    }
    try append_fmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

pub fn union_payload_comparison_call_branch(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?UnionBranch {
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tok_eq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, args_end);
    if (second_end != args_end) return null;
    const range = trim_parens(tokens, args_start, first_end);
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return null;
    const layout = func.result_union orelse return null;
    return union_payload_comparison_branch_for_value(tokens, second_start, second_end, locals, ctx, layout);
}

pub fn emit_union_error_branch_comparison(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tok_eq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = union_local_single_ident(tokens, args_start, first_end, locals);
    const second_union = union_local_single_ident(tokens, second_start, second_end, locals);
    const union_local = first_union orelse second_union orelse return false;
    const value_start = if (first_union != null) second_start else args_start;
    const value_end = if (first_union != null) second_end else first_end;

    for (union_local.layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1) continue;
        const branch_value = error_branch_value_for_comparison(allocator, ctx, tokens, value_start, value_end, branch.ty) orelse continue;
        try append_union_tag_local_get(allocator, out, union_local.name);
        try append_fmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
        try out.appendSlice(allocator, "    i32.eq\n");
        try append_union_payload_local_get(allocator, out, union_local.name, branch.payload_start);
        try append_fmt(allocator, out, "    i32.const {d}\n", .{branch_value});
        try out.appendSlice(allocator, "    i32.eq\n");
        try out.appendSlice(allocator, "    i32.and\n");
        if (std.mem.eql(u8, call_name, "ne")) {
            try out.appendSlice(allocator, "    i32.eqz\n");
        }
        return true;
    }
    return false;
}

pub fn error_branch_value_for_comparison(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    error_ty: []const u8,
) ?usize {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return null;
    const name = tokens[range.start].lexeme;
    if (error_enum_branch_value(tokens, error_ty, name)) |value| return value;
    return imported_error_branch_value(allocator, ctx.imported_alias_ctx, tokens, name, error_ty);
}

pub fn emit_union_local_payload_for_type(allocator: std.mem.Allocator, name: []const u8, ty: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const union_local = find_union_local(locals.union_locals.items, name) orelse return false;
    const narrowed_ty = find_narrowed_union_type(locals.narrowed_union_locals.items, name) orelse
        return error.UnionPayloadRequiresNarrowing;
    const concrete_narrowed_ty = substitute_generic_type(narrowed_ty, ctx.type_bindings);

    // Prefer branch matching the narrowed payload/arm type.
    var matched: ?UnionBranch = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len == 0) continue;
        const branch_payload_ty = branch.payload_type orelse branch.ty;
        const concrete_branch_ty = substitute_generic_type(branch_payload_ty, ctx.type_bindings);
        // Match narrowed type to case name or payload type.
        const matches_narrow = codegen_types_compatible(concrete_branch_ty, concrete_narrowed_ty) or
            std.mem.eql(u8, branch.ty, concrete_narrowed_ty);
        if (!matches_narrow) continue;
        if (!codegen_types_compatible(concrete_branch_ty, ty) and !codegen_types_compatible(branch.ty, ty)) continue;
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
            const concrete_branch_ty = substitute_generic_type(branch_payload_ty, ctx.type_bindings);
            if (!codegen_types_compatible(concrete_branch_ty, ty) and !codegen_types_compatible(branch.ty, ty)) continue;
            if (matched != null) return false;
            matched = branch;
        }
    }
    const branch = matched orelse return false;

    const branch_payload_ty = branch.payload_type orelse branch.ty;
    if (!codegen_types_compatible(concrete_narrowed_ty, ty) and
        !std.mem.eql(u8, concrete_narrowed_ty, branch.ty) and
        !codegen_types_compatible(concrete_narrowed_ty, branch_payload_ty))
        return false;

    try append_union_payload_local_get(allocator, out, union_local.name, branch.payload_start);
    return true;
}

/// Pop ABI union slots from the stack into `union_local` (payloads then tag).
fn store_union_local_from_stack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    union_local: UnionLocal,
) !void {
    var idx = union_local.layout.payload_tys.len + 1;
    while (idx > 0) {
        idx -= 1;
        if (idx == union_local.layout.payload_tys.len) {
            try append_union_tag_local_set(allocator, out, union_local.name);
        } else {
            try append_union_payload_local_set(allocator, out, union_local.name, idx);
        }
    }
}

fn emit_union_binding_from_user_func(
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
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
    const func_union = func.result_union orelse return false;
    if (!union_layouts_abi_compatible(ctx, func_union, union_local.layout)) return false;

    if (!try codegen_callbacks.emit_user_func_call_with_union_binding_move(
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

    try store_union_local_from_stack(allocator, out, union_local);
    return true;
}

fn emit_union_binding_from_wasi(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    union_local: UnionLocal,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    // Fallible host result-area → exclusive do union (`nil|i32`, `Dir|i32`, …).
    const wasi_import = find_wasi_host_import_for_tokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    const emitted =
        try emit_wasi_unit_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_descriptor_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_filesize_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_list_u8_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, codegen_callbacks.emit_expr) or
        try emit_wasi_read_result_as_union_value(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, union_local.layout, out, codegen_callbacks.emit_expr);
    if (!emitted) return false;

    try store_union_local_from_stack(allocator, out, union_local);
    return true;
}

fn emit_union_binding_from_call(
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
    const call_head = expr_call_head(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;

    if (try emit_union_binding_from_user_func(
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

    return emit_union_binding_from_wasi(allocator, tokens, call_head, locals, ctx, union_local, out);
}

pub fn emit_union_binding(
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
    const union_local = find_union_local(locals.union_locals.items, tokens[start_idx].lexeme) orelse return false;
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    const rhs_range = trim_parens(tokens, eq_idx + 1, end_idx);

    if (try emit_union_binding_from_call(
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

    if (!try emit_union_value(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, union_local.layout, true, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    try store_union_local_from_stack(allocator, out, union_local);
    return true;
}

pub fn emit_union_struct_field_get_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, name: []const u8, field_tok: lexer.Token, single_field_arg: bool, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    if (!single_field_arg or !is_dot_ident(field_tok.lexeme)) return false;
    const union_local = find_union_local(locals.union_locals.items, name) orelse return false;
    const payload = union_local_default_struct_payload(tokens, ctx, union_local) orelse return false;
    const field_name = public_decl_name(field_tok.lexeme);
    const field_offset = struct_field_payload_offset(payload.decl, field_name) orelse return false;

    if (payload.branch.payload_len == 1) {
        if (find_struct_layout(ctx.struct_layouts, payload.decl.name)) |layout| {
            const field_ty = find_struct_field_type(payload.decl, field_name) orelse return false;
            try append_union_payload_local_get(allocator, out, name, payload.branch.payload_start);
            try out.appendSlice(allocator, "    call $__arc_payload\n");
            try append_fmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
            try append_load_for_payload_type(allocator, out, field_ty);
            if (is_managed_struct_field(layout, field_name)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            return true;
        }
    }

    var idx = payload.branch.payload_start;
    var offset: usize = 0;
    for (payload.decl.fields) |field| {
        offset = align_up(offset, type_payload_alignment(field.ty));
        if (std.mem.eql(u8, public_decl_name(field.name), field_name)) {
            try append_union_payload_local_get(allocator, out, name, idx);
            return true;
        }
        offset += type_payload_bytes(field.ty);
        idx += 1;
    }
    return false;
}

pub fn imported_error_branch_value(
    allocator: std.mem.Allocator,
    imported_alias_ctx: ?ImportedAliasContext,
    tokens: []const lexer.Token,
    name: []const u8,
    enum_name: []const u8,
) ?usize {
    const ctx = imported_alias_ctx orelse return null;
    const import_ref = find_codegen_import_by_alias(tokens, name) orelse return null;
    const child_idx = find_imported_module_index(allocator, ctx.graph, ctx.module_idx, import_ref) orelse return null;
    return error_enum_branch_value(ctx.graph.modules[child_idx].tokens, enum_name, import_ref.target);
}

pub fn collect_union_return_move_names(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext, layout: UnionLayout, move_names: *std.ArrayList([]const u8)) !void {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return;
    const name = tokens[range.start].lexeme;
    if (find_union_local(locals.union_locals.items, name)) |union_local| {
        if (!union_layouts_abi_compatible(ctx, union_local.layout, layout)) return;
        for (layout.payload_tys, 0..) |payload_ty, idx| {
            if (!is_managed_local_type(payload_ty, ctx)) continue;
            const payload_name = try union_payload_local_name(allocator, union_local.name, idx);
            defer allocator.free(payload_name);
            const local_name = find_local_name(locals.locals.items, payload_name) orelse return;
            try move_names.append(allocator, local_name);
        }
        return;
    }
    const raw_ty = find_local_type(locals.locals.items, name) orelse return;
    const ty = substitute_generic_type(raw_ty, ctx.type_bindings);
    if (!is_managed_local_type(ty, ctx)) return;
    if (find_union_branch_by_compatible_type(layout, ty) == null and !union_layout_has_single_payload_abi_type(ctx, layout, ty)) return;
    try move_names.append(allocator, find_local_name(locals.locals.items, name) orelse name);
}

pub fn union_layout_has_single_payload_abi_type(ctx: CodegenContext, layout: UnionLayout, ty: []const u8) bool {
    const target_wasm_ty = codegen_wasm_type(ctx, ty);
    for (layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        const payload_ty = layout.payload_tys[branch.payload_start];
        if (std.mem.eql(u8, codegen_wasm_type(ctx, payload_ty), target_wasm_ty)) return true;
    }
    return false;
}

pub fn union_payload_comparison_branch_for_value(
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
        if (!is_codegen_scalar_type(ctx, branch.ty)) continue;
        if (!call_arg_matches_param(tokens, value_start, value_end, locals, ctx, branch.ty)) continue;
        return branch;
    }
    return null;
}

pub fn emit_union_payload_comparison_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tok_eq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, args_end);
    if (second_end != args_end) return false;
    const range = trim_parens(tokens, args_start, first_end);
    const call_head = expr_call_head(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = find_func_decl_for_call_head(tokens, call_head, locals, ctx) orelse return false;
    const layout = func.result_union orelse return false;
    const branch = union_payload_comparison_branch_for_value(tokens, second_start, second_end, locals, ctx, layout) orelse return false;

    if (!try codegen_callbacks.emit_user_func_call_with_move_context(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, null, out)) {
        return false;
    }
    try append_fmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (!try codegen_callbacks.emit_expr(allocator, tokens, second_start, second_end, locals, ctx, branch.ty, out)) {
        return false;
    }
    const op_ty = codegen_scalar_type(ctx, branch.ty);
    const eq_op = comparison_wasm_op("eq", op_ty) orelse return false;
    try append_fmt(allocator, out, "    {s}\n", .{eq_op});
    try append_fmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try append_fmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    i32.and\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

pub fn emit_union_payload_comparison_local(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, call_name: []const u8, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const first_end = find_arg_end(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tok_eq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = union_local_single_ident(tokens, args_start, first_end, locals);
    const second_union = union_local_single_ident(tokens, second_start, second_end, locals);
    if (first_union != null and second_union != null) return false;

    const union_local = first_union orelse second_union orelse return false;
    const value_start = if (first_union != null) second_start else args_start;
    const value_end = if (first_union != null) second_end else first_end;
    const branch = union_payload_comparison_branch_for_local_value(tokens, value_start, value_end, locals, ctx, union_local.layout) orelse return false;

    try append_union_payload_local_get(allocator, out, union_local.name, branch.payload_start);
    if (!try codegen_callbacks.emit_expr(allocator, tokens, value_start, value_end, locals, ctx, branch.ty, out)) {
        return false;
    }
    const op_ty = codegen_scalar_type(ctx, branch.ty);
    const eq_op = comparison_wasm_op("eq", op_ty) orelse return false;
    try append_fmt(allocator, out, "    {s}\n", .{eq_op});
    try append_union_tag_local_get(allocator, out, union_local.name);
    try append_fmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    i32.and\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

pub fn union_payload_comparison_branch_for_local_value(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
) ?UnionBranch {
    for (layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1) continue;
        if (!is_codegen_scalar_type(ctx, branch.ty)) continue;
        if (!call_arg_matches_param(tokens, value_start, value_end, locals, ctx, branch.ty)) continue;
        return branch;
    }
    return null;
}

pub fn union_local_single_ident(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?UnionLocal {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return null;
    return find_union_local(locals.union_locals.items, tokens[range.start].lexeme);
}

pub fn find_storage_readable_local_name(
    tokens: []const lexer.Token,
    locals: *const LocalSet,
    name: []const u8,
) ?[]const u8 {
    _ = tokens;
    if (find_storage_primitive_local(locals.storage_locals.items, name)) |storage| return storage.name;

    const ty = find_narrowed_union_type(locals.narrowed_union_locals.items, name) orelse return null;
    if (storage_elem_type_from_name(ty) == null) return null;
    const union_local = find_union_local(locals.union_locals.items, name) orelse return null;

    var matched: ?UnionBranch = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        if (!codegen_types_compatible(branch.ty, ty)) continue;
        if (matched != null) return null;
        matched = branch;
    }
    const branch = matched orelse return null;
    return union_payload_local_name_from_locals(locals.locals.items, union_local.name, branch.payload_start);
}

pub fn emit_union_storage_payload_get_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, name: []const u8, index_start: usize, index_end: usize, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) CodegenError!bool {
    const ty = find_narrowed_union_type(locals.narrowed_union_locals.items, name) orelse return false;
    const elem_ty = storage_elem_type_from_name(ty) orelse return false;
    const elem_bytes = storage_element_byte_width_for_type(elem_ty, ctx) orelse return false;
    const storage_name = find_storage_readable_local_name(tokens, locals, name) orelse return false;

    try emit_storage_bounds_check(allocator, tokens, index_start, index_end, locals, ctx, storage_name, 1, out);
    if (is_tuple_type_name(elem_ty)) {
        try emit_storage_data_ptr(allocator, out, storage_name);
        if (!try codegen_callbacks.emit_expr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
        if (elem_bytes != 1) {
            try append_fmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try append_fmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try append_load_tuple_leaves_owning_to_stack_ctx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emit_storage_data_ptr(allocator, out, storage_name);
        if (!try codegen_callbacks.emit_expr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
        if (elem_bytes != 1) {
            try append_fmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try append_load_for_payload_type(allocator, out, elem_ty);
        if (is_managed_local_type(elem_ty, ctx)) {
            try out.appendSlice(allocator, "    ;; storage-managed-get-inc\n");
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    return true;
}

pub fn is_codegen_scalar_type(ctx: CodegenContext, ty: []const u8) bool {
    return is_core_wasm_scalar(ty) or value_enum_carrier(ctx, ty) != null;
}

pub fn is_unsigned_scalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "u8") or
        std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "u32") or
        std.mem.eql(u8, ty, "u64") or
        std.mem.eql(u8, ty, "usize");
}

pub fn comparison_wasm_op(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasm_type(ty);
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
        if (std.mem.eql(u8, wt, "i64")) return if (is_unsigned_scalar(ty)) "i64.lt_u" else "i64.lt_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.lt";
        if (std.mem.eql(u8, wt, "f64")) return "f64.lt";
        return if (is_unsigned_scalar(ty)) "i32.lt_u" else "i32.lt_s";
    }
    if (std.mem.eql(u8, name, "le")) {
        if (std.mem.eql(u8, wt, "i64")) return if (is_unsigned_scalar(ty)) "i64.le_u" else "i64.le_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.le";
        if (std.mem.eql(u8, wt, "f64")) return "f64.le";
        return if (is_unsigned_scalar(ty)) "i32.le_u" else "i32.le_s";
    }
    if (std.mem.eql(u8, name, "gt")) {
        if (std.mem.eql(u8, wt, "i64")) return if (is_unsigned_scalar(ty)) "i64.gt_u" else "i64.gt_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.gt";
        if (std.mem.eql(u8, wt, "f64")) return "f64.gt";
        return if (is_unsigned_scalar(ty)) "i32.gt_u" else "i32.gt_s";
    }
    if (std.mem.eql(u8, name, "ge")) {
        if (std.mem.eql(u8, wt, "i64")) return if (is_unsigned_scalar(ty)) "i64.ge_u" else "i64.ge_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.ge";
        if (std.mem.eql(u8, wt, "f64")) return "f64.ge";
        return if (is_unsigned_scalar(ty)) "i32.ge_u" else "i32.ge_s";
    }
    return null;
}
