;; Linear-memory ARC oracle for the mixed scalar/list record lower route.
(module
  (type $canonical_lower (func (param i32 i32 i32 i32 i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0" "write" (func $canonical_call (type $canonical_lower)))
  (memory (export "memory") 1)
  (data (i32.const 16) "hello")
  (data (i32.const 32) "\0a\14\05")
  (global $__marshal_heap (mut i32) (i32.const 64))
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
  (export "cabi_realloc" (func $cabi_realloc))
  (func $run (result i32)
    (local $label_ptr i32)
    (local $payload_ptr i32)
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 5
    call $cabi_realloc
    local.set $label_ptr
    local.get $label_ptr
    i32.const 16
    i32.const 5
    memory.copy
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 3
    call $cabi_realloc
    local.set $payload_ptr
    local.get $payload_ptr
    i32.const 32
    i32.const 3
    memory.copy
    i32.const 7
    local.get $label_ptr
    i32.const 5
    local.get $payload_ptr
    i32.const 3
    call $canonical_call
    local.get $payload_ptr
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
  (export "run" (func $run))
)
