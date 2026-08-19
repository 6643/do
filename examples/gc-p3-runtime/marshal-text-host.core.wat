;; Host-driven bounded lower probe. The guest constructs a GC text value,
;; marshals it through linear memory, and calls the canonical string import.
(module
  (type $do_bytes (array (mut i8)))
  (type $do_text (struct (field $length i32) (field $bytes (ref null $do_bytes))))
  (type $canonical_lower (func (param i32 i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-host/api@1.0.0" "send" (func $canonical_call (type $canonical_lower)))
  (memory (export "memory") 1)
  (global $__marshal_heap (mut i32) (i32.const 16))
  (func $cabi_realloc (type $cabi_realloc_type)
    (param $old i32)
    (param $old_size i32)
    (param $align i32)
    (param $size i32)
    (result i32)
    (local $ptr i32)
    local.get $old
    i32.eqz
    if (result i32)
      global.get $__marshal_heap
      local.tee $ptr
      global.get $__marshal_heap
      local.get $size
      i32.add
      global.set $__marshal_heap
    else
      i32.const 0
    end)
  (export "cabi_realloc" (func $cabi_realloc))
  (func $marshal (param $input (ref null $do_text))
    (local $__gc_length i32)
    (local $__gc_index i32)
    (local $__cabi_ptr i32)
    (local $__memory_bytes i64)
    local.get $input
    ref.as_non_null
    struct.get $do_text $length
    local.set $__gc_length
    local.get $__gc_length
    local.get $input
    ref.as_non_null
    struct.get $do_text $bytes
    ref.as_non_null
    array.len
    i32.gt_u
    if unreachable end
    i32.const 0
    i32.const 0
    i32.const 1
    local.get $__gc_length
    call $cabi_realloc
    local.set $__cabi_ptr
    memory.size
    i64.extend_i32_u
    i64.const 65536
    i64.mul
    local.set $__memory_bytes
    local.get $__cabi_ptr
    i64.extend_i32_u
    local.get $__memory_bytes
    i64.gt_u
    if unreachable end
    local.get $__gc_length
    i64.extend_i32_u
    local.get $__memory_bytes
    local.get $__cabi_ptr
    i64.extend_i32_u
    i64.sub
    i64.gt_u
    if unreachable end
    i32.const 0
    local.set $__gc_index
    block $__copy_done
      loop $__copy
        local.get $__gc_index
        local.get $__gc_length
        i32.ge_u
        br_if $__copy_done
        local.get $__cabi_ptr
        local.get $__gc_index
        i32.add
        local.get $input
        ref.as_non_null
        struct.get $do_text $bytes
        ref.as_non_null
        local.get $__gc_index
        array.get_s $do_bytes
        i32.store8
        local.get $__gc_index
        i32.const 1
        i32.add
        local.set $__gc_index
        br $__copy
      end
    end
    local.get $__cabi_ptr
    local.get $__gc_length
    call $canonical_call
    local.get $__cabi_ptr
    local.get $__gc_length
    i32.const 1
    i32.const 0
    call $cabi_realloc
    drop)
  (func $run
    i32.const 5
    i32.const 104
    i32.const 101
    i32.const 108
    i32.const 108
    i32.const 111
    array.new_fixed $do_bytes 5
    struct.new $do_text
    call $marshal)
  (export "run" (func $run))
)
