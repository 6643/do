;; Fixed linear-memory lower/copy/call path for the ARC/GC equivalence gate.
(module
  (type $canonical_lower (func (param i32 i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-equivalence/api@1.0.0" "send" (func $canonical_call (type $canonical_lower)))
  (memory (export "memory") 1)
  (global $__marshal_heap (mut i32) (i32.const 32))
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
  (data (i32.const 16) "hello")
  (func $run (result i32)
    (local $ptr i32)
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 5
    call $cabi_realloc
    local.set $ptr
    local.get $ptr
    i32.const 16
    i32.const 5
    memory.copy
    local.get $ptr
    i32.const 5
    call $canonical_call
    local.get $ptr
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
