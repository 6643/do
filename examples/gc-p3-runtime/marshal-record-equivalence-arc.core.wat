;; Linear-memory record-result path for ARC/GC semantic equivalence.
(module
  (type $canonical_lift (func (param i32)))
  (import "demo:marshal-record-equivalence/api@1.0.0" "read" (func $canonical_call (type $canonical_lift)))
  (memory (export "memory") 1)
  (func $run (result i32)
    i32.const 0
    call $canonical_call
    i32.const 0
    i32.load
    i32.const 4
    i32.load
    i32.add)
  (export "run" (func $run))
)
