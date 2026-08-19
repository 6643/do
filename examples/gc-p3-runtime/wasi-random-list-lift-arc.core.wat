(module
  (type $canonical_lift (func (param i64 i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "wasi:random/random@0.3.0-rc-2025-09-16" "get-random-bytes" (func $canonical_call (type $canonical_lift)))
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
      local.set $ptr
      global.get $__marshal_heap
      local.get $size
      i32.add
      global.set $__marshal_heap
      local.get $ptr
    else
      i32.const 0
    end)
  (export "cabi_realloc" (func $cabi_realloc))
  (func $run (result i32)
    i64.const 16
    i32.const 0
    call $canonical_call
    i32.const 4
    i32.load)
  (export "run" (func $run))
)
