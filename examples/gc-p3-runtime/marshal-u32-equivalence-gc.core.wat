;; Fixed GC list<u32> lower/copy/call path for ARC/GC equivalence.
(module
  (type $do_u32 (array (mut i32)))
  (type $canonical_lower (func (param i32 i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-u32-equivalence/api@1.0.0" "send" (func $canonical_call (type $canonical_lower)))
  (memory (export "memory") 1)
  (global $__marshal_heap (mut i32) (i32.const 16))
  (global $__alloc_count (mut i32) (i32.const 0))
  (global $__free_count (mut i32) (i32.const 0))
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
      global.get $__alloc_count
      i32.const 1
      i32.add
      global.set $__alloc_count
      global.get $__marshal_heap
      local.tee $ptr
      global.get $__marshal_heap
      local.get $size
      i32.add
      global.set $__marshal_heap
    else
      global.get $__free_count
      i32.const 1
      i32.add
      global.set $__free_count
      i32.const 0
    end)
  (func $marshal (param $input (ref null $do_u32))
    (local $__gc_length i32)
    (local $__gc_index i32)
    (local $__cabi_ptr i32)
    local.get $input
    ref.as_non_null
    array.len
    local.set $__gc_length
    i32.const 0
    i32.const 0
    i32.const 4
    local.get $__gc_length
    i32.const 4
    i32.mul
    call $cabi_realloc
    local.set $__cabi_ptr
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
    local.get $__gc_length
    i32.const 4
    i32.mul
    i32.const 4
    i32.const 0
    call $cabi_realloc
    drop)
  (func $run (result i32)
    i32.const 10
    i32.const 20
    i32.const 30
    array.new_fixed $do_u32 3
    call $marshal
    global.get $__alloc_count
    i32.const 16
    i32.mul
    global.get $__free_count
    i32.add)
  (export "run" (func $run))
)
