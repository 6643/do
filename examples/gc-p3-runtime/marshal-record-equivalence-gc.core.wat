;; GC record-result path for ARC/GC semantic equivalence.
(module
  (type $do_record (struct (field $field0 i32) (field $field1 i32)))
  (type $canonical_lift (func (param i32)))
  (import "demo:marshal-record-equivalence/api@1.0.0" "read" (func $canonical_call (type $canonical_lift)))
  (memory (export "memory") 1)
  (func $run (result i32)
    (local $reading (ref null $do_record))
    i32.const 0
    call $canonical_call
    i32.const 0
    i32.load
    i32.const 4
    i32.load
    struct.new $do_record
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
