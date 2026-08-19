;; Linear-memory reference path for indirect scalar-record lower equivalence.
(module
  (type $canonical_lower (func (param i32)))
  (import "demo:marshal-record-indirect-lower/api@1.0.0" "write" (func $canonical_call (type $canonical_lower)))
  (memory (export "memory") 1)
  (func $run (result i32)
    i32.const 16
    i64.const 1
    i64.store
    i32.const 16
    i64.const 2
    i64.store offset=8
    i32.const 16
    i64.const 3
    i64.store offset=16
    i32.const 16
    i64.const 4
    i64.store offset=24
    i32.const 16
    i64.const 5
    i64.store offset=32
    i32.const 16
    i64.const 6
    i64.store offset=40
    i32.const 16
    i64.const 7
    i64.store offset=48
    i32.const 16
    i64.const 8
    i64.store offset=56
    i32.const 16
    i64.const 9
    i64.store offset=64
    i32.const 16
    i64.const 10
    i64.store offset=72
    i32.const 16
    i64.const 11
    i64.store offset=80
    i32.const 16
    i64.const 12
    i64.store offset=88
    i32.const 16
    i64.const 13
    i64.store offset=96
    i32.const 16
    i64.const 14
    i64.store offset=104
    i32.const 16
    i64.const 15
    i64.store offset=112
    i32.const 16
    i64.const 16
    i64.store offset=120
    i32.const 16
    i64.const 17
    i64.store offset=128
    i32.const 16
    call $canonical_call
    i32.const 42)
  (export "run" (func $run))
)
