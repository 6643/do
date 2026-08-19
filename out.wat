(module
  ;; gc-sync source_len=654 token_count=142
  (type $do_bytes (array (mut i8)))
  (type $do_text (struct (field $length i32) (field $bytes (ref null $do_bytes))))
  (type $do_bool (array (mut i32)))
  (type $do_i8 (array (mut i32)))
  (type $do_i16 (array (mut i32)))
  (type $do_i32 (array (mut i32)))
  (type $do_i64 (array (mut i64)))
  (type $do_u16 (array (mut i32)))
  (type $do_u32 (array (mut i32)))
  (type $do_u64 (array (mut i64)))
  (type $do_isize (array (mut i32)))
  (type $do_usize (array (mut i32)))
  (type $do_f32 (array (mut f32)))
  (type $do_f64 (array (mut f64)))
  (type $box (struct (field $value (ref null $do_text)) (field $tag i32)))
  (type $tuple_text_bytes (struct (field $text (ref null $do_text)) (field $bytes (ref null $do_bytes))))
  (func $make_text (result (ref null $do_text))
    (local $__gc_nested_box (ref null $box))
    (local $__gc_list_next (ref null $do_bytes))
    (local $__gc_bool_list_next (ref null $do_bool))
    (local $__gc_i8_list_next (ref null $do_i8))
    (local $__gc_i16_list_next (ref null $do_i16))
    (local $__gc_i32_list_next (ref null $do_i32))
    (local $__gc_i64_list_next (ref null $do_i64))
    (local $__gc_u16_list_next (ref null $do_u16))
    (local $__gc_u32_list_next (ref null $do_u32))
    (local $__gc_u64_list_next (ref null $do_u64))
    (local $__gc_isize_list_next (ref null $do_isize))
    (local $__gc_usize_list_next (ref null $do_usize))
    (local $__gc_f32_list_next (ref null $do_f32))
    (local $__gc_f64_list_next (ref null $do_f64))
    (local $__gc_list_length i32)
    ;; gc-root return_value
    i32.const 5
    i32.const 102
    i32.const 114
    i32.const 101
    i32.const 115
    i32.const 104
    array.new_fixed $do_bytes 5
    struct.new $do_text
    return
  )
  (func $replace (param $box (ref null $box)) (result (ref null $box))
    (local $__gc_nested_box (ref null $box))
    (local $__gc_list_next (ref null $do_bytes))
    (local $__gc_bool_list_next (ref null $do_bool))
    (local $__gc_i8_list_next (ref null $do_i8))
    (local $__gc_i16_list_next (ref null $do_i16))
    (local $__gc_i32_list_next (ref null $do_i32))
    (local $__gc_i64_list_next (ref null $do_i64))
    (local $__gc_u16_list_next (ref null $do_u16))
    (local $__gc_u32_list_next (ref null $do_u32))
    (local $__gc_u64_list_next (ref null $do_u64))
    (local $__gc_isize_list_next (ref null $do_isize))
    (local $__gc_usize_list_next (ref null $do_usize))
    (local $__gc_f32_list_next (ref null $do_f32))
    (local $__gc_f64_list_next (ref null $do_f64))
    (local $__gc_list_length i32)
    ;; gc-root local_bind $box
    ;; gc-root return_value
    call $make_text
    ;; gc-root call_result
    local.get $box
    ref.as_non_null
    struct.get $box $tag
    struct.new $box
    return
  )
  ;; compiled-test 0 "compiled managed text field call producer preserves source"
  (func $__test_0
    (local $old (ref null $do_text))
    (local $box (ref null $box))
    (local $updated (ref null $box))
    (local $original_value (ref null $do_text))
    (local $updated_value (ref null $do_text))
    (local $original_len i32)
    (local $updated_len i32)
    (local $updated_tag i32)
    (local $__gc_nested_box (ref null $box))
    (local $__gc_list_next (ref null $do_bytes))
    (local $__gc_bool_list_next (ref null $do_bool))
    (local $__gc_i8_list_next (ref null $do_i8))
    (local $__gc_i16_list_next (ref null $do_i16))
    (local $__gc_i32_list_next (ref null $do_i32))
    (local $__gc_i64_list_next (ref null $do_i64))
    (local $__gc_u16_list_next (ref null $do_u16))
    (local $__gc_u32_list_next (ref null $do_u32))
    (local $__gc_u64_list_next (ref null $do_u64))
    (local $__gc_isize_list_next (ref null $do_isize))
    (local $__gc_usize_list_next (ref null $do_usize))
    (local $__gc_f32_list_next (ref null $do_f32))
    (local $__gc_f64_list_next (ref null $do_f64))
    (local $__gc_list_length i32)
    i32.const 3
    i32.const 111
    i32.const 108
    i32.const 100
    array.new_fixed $do_bytes 3
    struct.new $do_text
    local.set $old
    ;; gc-root local_bind $old
    local.get $old
    i32.const 7
    struct.new $box
    local.set $box
    ;; gc-root local_bind $box
    local.get $box
    call $replace
    ;; gc-root call_result
    local.set $updated
    ;; gc-root local_bind $updated
    local.get $box
    ref.as_non_null
    struct.get $box $value
    local.set $original_value
    ;; gc-root local_bind $original_value
    local.get $updated
    ref.as_non_null
    struct.get $box $value
    local.set $updated_value
    ;; gc-root local_bind $updated_value
    local.get $original_value
    ref.as_non_null
    struct.get $do_text $length
    local.set $original_len
    local.get $updated_value
    ref.as_non_null
    struct.get $do_text $length
    local.set $updated_len
    local.get $updated
    ref.as_non_null
    struct.get $box $tag
    local.set $updated_tag
    local.get $original_len
    i32.const 3
    i32.eq
    if
    local.get $updated_len
    i32.const 5
    i32.eq
    if
    local.get $updated_tag
    i32.const 7
    i32.eq
    if
    return
    end
    ;; gc-root guard_join
    end
    ;; gc-root branch_join
    end
    ;; gc-root branch_join
    unreachable
  )
  (export "__test_0" (func $__test_0))
  (func $_start
    call $__test_0
  )
  (export "_start" (func $_start))
)
