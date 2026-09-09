//! Codegen ABI, layout, and temporary-local constants.
// Keep scalar/layout constants independent from the legacy ARC storage
// emitter. Both the GC and equivalence routes consume these stable values.
pub const TYPE_ID_STORAGE_U8: usize = 1;
pub const TYPE_ID_STORAGE_MANAGED: usize = 65535;
pub const TYPE_ID_FIRST_STRUCT: usize = TYPE_ID_STORAGE_U8 + 1;
pub const STORAGE_PAYLOAD_HEADER_BYTES: usize = 8;
pub const STORAGE_OVERWRITE_TMP_LOCAL = "__storage_overwrite_tmp";
pub const WASI_FAMILY_TMP_LOCAL = "__wasi_family_tmp";
pub const STORAGE_PUT_SOURCE_TMP_LOCAL = "__storage_put_source_tmp";
pub const VARIADIC_PACK_TMP_LOCAL = "__variadic_pack_tmp";
pub const STORAGE_WRITE_INDEX_TMP_LOCAL = "__storage_write_index_tmp";
pub const STORAGE_WRITE_LEN_TMP_LOCAL = "__storage_write_len_tmp";
pub const STORAGE_WRITE_NEXT_TMP_LOCAL = "__storage_write_next_tmp";
pub const STORAGE_WRITE_SCAN_TMP_LOCAL = "__storage_write_scan_tmp";
pub const STORAGE_WRITE_TARGET_TMP_LOCAL = "__storage_write_target_tmp";
pub const TUPLE_PACK_BASE_TMP_LOCAL = "__tuple_pack_base_tmp";
pub const TUPLE_PACK_SPILL_I32 = "__tuple_pack_spill_i32";
pub const TUPLE_PACK_SPILL_I64 = "__tuple_pack_spill_i64";
pub const TUPLE_PACK_SPILL_F32 = "__tuple_pack_spill_f32";
pub const TUPLE_PACK_SPILL_F64 = "__tuple_pack_spill_f64";
pub const STRUCT_LITERAL_TMP_LOCAL = "__struct_literal_tmp";
pub const NUMERIC_SELECT_LEFT_TMP_I32 = "__numeric_select_left_i32";
pub const NUMERIC_SELECT_RIGHT_TMP_I32 = "__numeric_select_right_i32";
pub const NUMERIC_SELECT_LEFT_TMP_I64 = "__numeric_select_left_i64";
pub const NUMERIC_SELECT_RIGHT_TMP_I64 = "__numeric_select_right_i64";
