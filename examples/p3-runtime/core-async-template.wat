;; A minimal legacy stackless async ABI state machine. This fixture is
;; componentized by test_core_async_template.sh.
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

  (func (export "[async-lift]run") (type $async-run) (local $subtask i32) (local $waitable-set i32)
    call $waitable-set-new
    local.tee $waitable-set
    call $context-set-0
    local.get 0
    call $wait-for
    local.set $subtask
    local.get $subtask
    i32.const 4
    i32.shr_u
    local.get $waitable-set
    call $waitable-join
    local.get $waitable-set
    i32.const 4
    i32.shl
    i32.const 2
    i32.or
  )
  (func (export "[callback][async-lift]run") (type $async-run-callback) (local $waitable-set i32)
    call $context-get-0
    local.set $waitable-set
    local.get 0
    i32.const 1
    i32.eq
    local.get 2
    i32.const 2
    i32.eq
    i32.and
    if (result i32)
      call $task-return
      i32.const 0
    else
      local.get $waitable-set
      i32.const 4
      i32.shl
      i32.const 2
      i32.or
    end
  )
  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable
  )
  (func (export "_initialize"))
  (@custom "component-type" (after code) "\00asm\0d\00\01\00\00\19\16wit-component-encoding\04\00\07~\01A\02\01A\04\01B\02\01C\01\08how-longw\01\00\04\00\08wait-for\01\00\03\00!wasi:clocks/monotonic-clock@0.3.0\05\00\01C\01\08how-longw\01\00\04\00\03run\01\01\04\00\17wasi:clocks/probe@0.3.0\04\00\0b\0b\01\00\05probe\03\00\00\00/\09producers\01\0cprocessed-by\01\0dwit-component\070.254.0")
)
