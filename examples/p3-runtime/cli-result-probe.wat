(module
  (type $async-lower-run (func (param i32) (result i32)))
  (type $task-return (func (param i32)))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $async-run (func (result i32)))
  (type $async-run-callback (func (param i32 i32 i32) (result i32)))

  (import "wasi:cli/run@0.3.0" "[async-lower]run" (func $host-run (type $async-lower-run)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (param i32 i32) (result i32)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))

  (memory (export "memory") 1)

  (func (export "[async-lift]run") (type $async-run) (local $subtask i32) (local $set i32)
    call $waitable-set-new
    local.tee $set
    call $context-set-0
    i32.const 0
    call $host-run
    local.set $subtask
    local.get $subtask
    i32.const 4
    i32.shr_u
    local.get $set
    call $waitable-join
    local.get $set
    i32.const 4
    i32.shl
    i32.const 2
    i32.or
  )

  (func (export "[callback][async-lift]run") (type $async-run-callback) (local $set i32)
    call $context-get-0
    local.set $set
    local.get 0
    i32.const 1
    i32.eq
    local.get 2
    i32.const 2
    i32.eq
    i32.and
    if (result i32)
      i32.const 0
      i32.load
      call $task-return
      i32.const 0
    else
      local.get $set
      i32.const 4
      i32.shl
      i32.const 2
      i32.or
    end
  )
)
