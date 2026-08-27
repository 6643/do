;; Linear-memory three-level nested record lower path for manifest-backed ARC/GC equivalence.
(module
  (type $canonical_lower (func (param i32 i64 i64 i64)))
  (import "demo:marshal-record-nested-lower-deep/api@1.0.0" "write" (func $canonical_call (type $canonical_lower)))
  (func $run (result i32)
    i32.const 7
    i64.const 35
    i64.const -5
    i64.const 5
    call $canonical_call
    i32.const 42)
  (export "run" (func $run))
)
