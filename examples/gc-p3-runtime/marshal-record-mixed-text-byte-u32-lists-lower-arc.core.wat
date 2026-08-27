;; Linear-memory ARC oracle for the fixed mixed text/byte-u32-list record lower route.
(module
  (type $canonical_lower (func (param i32 i32 i32 i32 i32 i32 i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0" "write" (func $canonical_call (type $canonical_lower)))
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
    (local $label_ptr i32)
    (local $bytes_ptr i32)
    (local $values_ptr i32)
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 5
    call $cabi_realloc
    local.set $label_ptr
    local.get $label_ptr
    i32.const 104
    i32.store8
    local.get $label_ptr
    i32.const 1
    i32.add
    i32.const 101
    i32.store8
    local.get $label_ptr
    i32.const 2
    i32.add
    i32.const 108
    i32.store8
    local.get $label_ptr
    i32.const 3
    i32.add
    i32.const 108
    i32.store8
    local.get $label_ptr
    i32.const 4
    i32.add
    i32.const 111
    i32.store8
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 3
    call $cabi_realloc
    local.set $bytes_ptr
    local.get $bytes_ptr
    i32.const 10
    i32.store8
    local.get $bytes_ptr
    i32.const 1
    i32.add
    i32.const 20
    i32.store8
    local.get $bytes_ptr
    i32.const 2
    i32.add
    i32.const 5
    i32.store8
    i32.const 0
    i32.const 0
    i32.const 4
    i32.const 8
    call $cabi_realloc
    local.set $values_ptr
    local.get $values_ptr
    i32.const 3
    i32.store
    local.get $values_ptr
    i32.const 4
    i32.add
    i32.const 4
    i32.store
    i32.const 7
    local.get $label_ptr
    i32.const 5
    local.get $bytes_ptr
    i32.const 3
    local.get $values_ptr
    i32.const 2
    call $canonical_call
    local.get $values_ptr
    i32.const 8
    i32.const 4
    i32.const 0
    call $cabi_realloc
    drop
    local.get $bytes_ptr
    i32.const 3
    i32.const 1
    i32.const 0
    call $cabi_realloc
    drop
    local.get $label_ptr
    i32.const 5
    i32.const 1
    i32.const 0
    call $cabi_realloc
    drop
    global.get $__alloc_count
    i32.const 16
    i32.mul
    global.get $__free_count
    i32.add)
  (func $stats (result i32)
    global.get $__alloc_count
    i32.const 16
    i32.mul
    global.get $__free_count
    i32.add)
  (export "run" (func $run))
  (export "stats" (func $stats))
)
