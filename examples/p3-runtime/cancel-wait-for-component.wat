;; Standalone legacy async-callback cancellation fixture. The Component ABI
;; requires subtask.cancel to reach a terminal status before subtask.drop.
(module
  (type $async-lower-wait-for (func (param i64) (result i32)))
  (type $task-return (func))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $async-run (func (param i64) (result i32)))
  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "wasi:clocks/monotonic-clock@0.3.0" "[async-lower]wait-for"
    (func $wait-for (type $async-lower-wait-for)))
  (import "[export]$root" "[task-cancel]" (func $task-cancel))
  (import "$root" "[backpressure-inc]" (func $backpressure-inc))
  (import "$root" "[backpressure-dec]" (func $backpressure-dec))
  (import "$root" "[waitable-set-new]"
    (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (param i32 i32) (result i32)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (param i32 i32) (result i32)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (param i32)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[thread-yield]" (func $thread-yield (result i32)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (param i32)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (param i32) (result i32)))
  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
  (import "[export]$root" "[task-return]run"
    (func $task-return (type $task-return)))

  (memory (export "memory") 0)

  (func (export "[async-lift]run") (type $async-run)
    (local $subtask i32) (local $cancel-status i32)
    local.get 0
    call $wait-for
    local.tee $subtask
    i32.const 2
    i32.eq
    if (result i32)
      call $task-return
      i32.const 0
    else
      local.get $subtask
      i32.const 4
      i32.shr_u
      local.set $subtask
      local.get $subtask
      call $subtask-cancel
      local.tee $cancel-status
      i32.const 4
      i32.ne
      if
        unreachable
      end
      local.get $subtask
      call $subtask-drop
      call $task-return
      i32.const 0
    end
  )

  (func (export "[callback][async-lift]run") (type $async-run-callback)
    unreachable
  )

  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable
  )
  (func (export "_initialize"))
)
