(module
  (type $async-lower-send (func (param i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $async-probe (func (result i32)))
  (type $async-probe-callback (func (param i32 i32 i32) (result i32)))
  (type $root-noargs (func))
  (type $root-new (func (result i32)))
  (type $root-wait (func (param i32 i32) (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-cancel (func (param i32) (result i32)))
  ;; Pinned full HTTP error-code task-return shape. The payload words are
  ;; supplied by the canonical candidate in the runtime follow-up task.
  (type $task-return (func (param i32 i32 i32 i64 i32 i32 i32 i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"
    (func $send (type $async-lower-send)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"
    (func $drop-request (type $resource-drop)))
  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response"
    (func $drop-response (type $resource-drop)))
  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $root-noargs)))
  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $root-noargs)))
  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $root-noargs)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $root-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $root-wait)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $root-wait)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $resource-drop)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $root-join)))
  (import "$root" "[thread-yield]" (func $thread-yield (type $root-new)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $resource-drop)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $root-cancel)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $root-new)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $resource-drop)))
  (import "[export]wasi:http/probe@0.3.0-rc-2025-09-16" "[task-return]run"
    (func $task-return (type $task-return)))

  (memory (export "memory") 0)
  (func (export "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run")
    (type $async-probe)
    unreachable)
  (func (export "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run")
    (type $async-probe-callback)
    unreachable)
  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable)
  (func (export "_initialize") (type $root-noargs))
)
