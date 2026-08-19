;; Linear/flat reference path for scalar-record lower equivalence.
(module
  (type $canonical_lower (func (param i32 i32)))
  (import "demo:marshal-record-lower/api@1.0.0" "write" (func $canonical_call (type $canonical_lower)))
  (func $run (result i32)
    i32.const 7
    i32.const 35
    call $canonical_call
    i32.const 42)
  (export "run" (func $run))
)
