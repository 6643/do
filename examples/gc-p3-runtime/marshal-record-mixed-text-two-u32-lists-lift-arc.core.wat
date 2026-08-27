;; Linear-memory ARC oracle for the mixed text/two-u32-list record lift route.
(module
  (type $canonical_lift (func (param i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0" "read" (func $canonical_call (type $canonical_lift)))
  (memory (export "memory") 1)
  (global $__marshal_heap (mut i32) (i32.const 28))
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
      local.get $align
      i32.const 1
      i32.sub
      i32.add
      local.get $align
      i32.const 1
      i32.sub
      i32.const -1
      i32.xor
      i32.and
      local.tee $ptr
      local.get $size
      i32.add
      global.set $__marshal_heap
      local.get $ptr
    else
      global.get $__free_count
      i32.const 1
      i32.add
      global.set $__free_count
      i32.const 0
    end)
  (export "cabi_realloc" (func $cabi_realloc))
  (func $run (result i32)
    (local $__result_area i32)
    (local $code i32)
    (local $label_ptr i32)
    (local $label_length i32)
    (local $first_ptr i32)
    (local $first_length i32)
    (local $second_ptr i32)
    (local $second_length i32)
    (local $result i32)
    i32.const 0
    local.set $__result_area
    local.get $__result_area
    call $canonical_call
    local.get $__result_area
    i32.load
    local.set $code
    local.get $__result_area
    i32.const 4
    i32.add
    i32.load
    local.set $label_ptr
    local.get $__result_area
    i32.const 8
    i32.add
    i32.load
    local.set $label_length
    local.get $__result_area
    i32.const 12
    i32.add
    i32.load
    local.set $first_ptr
    local.get $__result_area
    i32.const 16
    i32.add
    i32.load
    local.set $first_length
    local.get $__result_area
    i32.const 20
    i32.add
    i32.load
    local.set $second_ptr
    local.get $__result_area
    i32.const 24
    i32.add
    i32.load
    local.set $second_length
    local.get $label_length
    i32.const 5
    i32.ne
    if unreachable end
    local.get $first_length
    i32.const 3
    i32.ne
    if unreachable end
    local.get $second_length
    i32.const 2
    i32.ne
    if unreachable end
    local.get $code
    local.get $label_length
    i32.add
    local.get $first_ptr
    i32.load
    i32.add
    local.get $first_ptr
    i32.const 4
    i32.add
    i32.load
    i32.add
    local.get $first_ptr
    i32.const 8
    i32.add
    i32.load
    i32.add
    local.get $second_ptr
    i32.load
    i32.add
    local.get $second_ptr
    i32.const 4
    i32.add
    i32.load
    i32.add
    local.set $result
    local.get $second_ptr
    local.get $second_length
    i32.const 4
    i32.mul
    i32.const 4
    i32.const 0
    call $cabi_realloc
    drop
    local.get $first_ptr
    local.get $first_length
    i32.const 4
    i32.mul
    i32.const 4
    i32.const 0
    call $cabi_realloc
    drop
    local.get $label_ptr
    local.get $label_length
    i32.const 1
    i32.const 0
    call $cabi_realloc
    drop
    local.get $result)
  (func $stats (result i32)
    global.get $__alloc_count
    i32.const 16
    i32.mul
    global.get $__free_count
    i32.add)
  (export "run" (func $run))
  (export "stats" (func $stats))
)
