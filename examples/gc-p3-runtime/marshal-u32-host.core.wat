;; Bounded host-driven lower probe for a GC list<u32>.
;; The canonical ABI receives (ptr, len) where len counts u32 elements.
(module
  (type $do_u32 (array (mut i32)))
  (type $canonical_lower (func (param i32 i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-u32-host/api@1.0.0" "send" (func $canonical_call (type $canonical_lower)))
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
  (func $marshal (param $input (ref null $do_u32))
    (local $__gc_length i32)
    (local $__gc_index i32)
    (local $__copy_bytes i32)
    (local $__copy_bytes64 i64)
    (local $__cabi_ptr i32)
    (local $__memory_bytes i64)
    local.get $input
    ref.as_non_null
    array.len
    local.set $__gc_length
    local.get $__gc_length
    i64.extend_i32_u
    i64.const 4
    i64.mul
    local.tee $__copy_bytes64
    i64.const 4294967295
    i64.gt_u
    if unreachable end
    local.get $__copy_bytes64
    i32.wrap_i64
    local.set $__copy_bytes
    i32.const 0
    i32.const 0
    i32.const 4
    local.get $__copy_bytes
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
    local.get $__copy_bytes
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
        i32.const 4
        i32.mul
        i32.add
        local.get $input
        ref.as_non_null
        local.get $__gc_index
        array.get $do_u32
        i32.store
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
    local.get $__copy_bytes
    i32.const 4
    i32.const 0
    call $cabi_realloc
    drop)
  (func $run
    i32.const 10
    i32.const 20
    i32.const 30
    array.new_fixed $do_u32 3
    call $marshal)
  (export "run" (func $run))
)
