(module
  (type $canonical_lift (func (param i32)))
  (type $cabi_realloc_type (func (param i32 i32 i32 i32) (result i32)))
  (import "demo:marshal-record-managed-lift-multi/api@1.0.0" "read" (func $canonical_call (type $canonical_lift)))
  (memory (export "memory") 1)
  (data (i32.const 16) "helloworld")
  (global $__marshal_heap (mut i32) (i32.const 32))
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
  (func $run (result i32)
    (local $__result_area i32)
    (local $code i32)
    (local $label_len i32)
    (local $note_len i32)
    i32.const 0
    local.set $__result_area
    local.get $__result_area
    call $canonical_call
    local.get $__result_area
    i32.load
    local.set $code
    local.get $__result_area
    i32.const 8
    i32.add
    i32.load
    local.set $label_len
    local.get $__result_area
    i32.const 16
    i32.add
    i32.load
    local.set $note_len
    local.get $code
    local.get $label_len
    i32.add
    local.get $note_len
    i32.add)
  (export "run" (func $run))
)
