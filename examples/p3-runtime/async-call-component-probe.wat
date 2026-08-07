;; Pinned ABI probe for an internal guest continuation.
;;
;; The `helper` function is deliberately not a WIT export.  The
;; `[task-return]helper` import below asks the Component async ABI to give that
;; internal function the same completion endpoint as an async-lifted export.
;; The probe must stay hand-written: accepting this import would be the
;; evidence required before adding a compiler lowering for guest child tasks.
(module
  (type $async-lower-work (func (result i32)))
  (type $task-return (func))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $waitable-set-wait (func (param i32 i32) (result i32)))
  (type $waitable-set-poll (func (param i32 i32) (result i32)))
  (type $waitable-set-drop (func (param i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $subtask-drop (func (param i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $thread-yield (func (result i32)))
  (type $async-run (func (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "do:generic-async-runtime-probe/host@0.1.0" "[async-lower]work"
    (func $host-work (type $async-lower-work)))
  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-return)))
  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $task-return)))
  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $task-return)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-set-wait)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-set-poll)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[thread-yield]" (func $thread-yield (type $thread-yield)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $subtask-drop)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
  (import "[export]$root" "[task-return]run" (func $task-return-run (type $task-return)))

  ;; This is the capability under test.  `helper` is intentionally absent from
  ;; the WIT world, so there is no corresponding async-lifted export.
  (import "[export]$root" "[task-return]helper" (func $task-return-helper (type $task-return)))

  (memory (export "memory") 0)

  (func $helper (result i32) (local $subtask i32)
    ;; [guest-async-child]
    call $host-work
    local.set $subtask
    ;; [guest-async-child-drop]
    local.get $subtask
    i32.const 4
    i32.shr_u
    drop
    i32.const 0
  )

  (func $helper-resume
    ;; [guest-async-parent-resume]
    call $task-return-helper
  )

  (func (export "[async-lift]run") (type $async-run)
    call $helper
    drop
    i32.const 0
  )

  (func (export "[callback][async-lift]run") (type $async-callback)
    call $helper-resume
    i32.const 0
  )

  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable
  )
  (func (export "_initialize"))
)
