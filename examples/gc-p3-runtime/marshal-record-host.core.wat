;; Bounded host-driven lift probe for a scalar record result.
;; The canonical ABI writes the record into the result-area pointer.
(module
  (type $do_record (struct (field $field0 i32) (field $field1 i32)))
  (type $canonical_lift (func (param i32)))
  (import "demo:marshal-record-host/api@1.0.0" "read" (func $canonical_call (type $canonical_lift)))
  (memory (export "memory") 1)
  (func $marshal (result (ref null $do_record))
    (local $__result_area i32)
    (local $__record_bytes i32)
    (local $__memory_bytes i64)
    i32.const 0
    local.set $__result_area
    local.get $__result_area
    call $canonical_call
    i32.const 8
    local.set $__record_bytes
    memory.size
    i64.extend_i32_u
    i64.const 65536
    i64.mul
    local.set $__memory_bytes
    local.get $__result_area
    i64.extend_i32_u
    local.get $__memory_bytes
    i64.gt_u
    if unreachable end
    local.get $__record_bytes
    i64.extend_i32_u
    local.get $__memory_bytes
    local.get $__result_area
    i64.extend_i32_u
    i64.sub
    i64.gt_u
    if unreachable end
    local.get $__result_area
    i32.const 0
    i32.add
    i32.load
    local.get $__result_area
    i32.const 4
    i32.add
    i32.load
    struct.new $do_record)
  (func $run (result i32)
    (local $reading (ref null $do_record))
    call $marshal
    local.set $reading
    local.get $reading
    ref.as_non_null
    struct.get $do_record $field0
    local.get $reading
    ref.as_non_null
    struct.get $do_record $field1
    i32.add)
  (export "run" (func $run))
)
