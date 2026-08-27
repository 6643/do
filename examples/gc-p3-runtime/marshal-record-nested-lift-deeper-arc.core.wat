;; Linear-memory four-level nested record-result path for manifest-backed ARC/GC equivalence.
(module
  (type $canonical_lift (func (param i32)))
  (import "demo:marshal-record-nested-lift-deeper/api@1.0.0" "read" (func $canonical_call (type $canonical_lift)))
  (memory (export "memory") 1)
  (func $run (result i32)
    i32.const 0
    call $canonical_call
    i32.const 0
    i32.load
    i32.const 8
    i64.load
    i32.wrap_i64
    i32.add
    i32.const 16
    i64.load
    i32.wrap_i64
    i32.add
    i32.const 24
    i64.load
    i32.wrap_i64
    i32.add
    i32.const 32
    i64.load
    i32.wrap_i64
    i32.add)
  (export "run" (func $run))
)
