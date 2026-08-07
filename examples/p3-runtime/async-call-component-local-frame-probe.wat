;; ABI probe for the fallback architecture: the guest helper is a local
;; continuation owned by the root async task.  It has no WIT export and no
;; synthetic `[task-return]helper` import; only the root owns task.return.
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

  (memory (export "memory") 1)
  (global $frame-next (mut i32) (i32.const 1024))

  ;; Frame offsets: waitable set @0, host subtask @4, helper state @8.
  (func $frame-alloc (result i32) (local $frame i32)
    global.get $frame-next
    local.tee $frame
    i32.const 16
    i32.add
    global.set $frame-next
    local.get $frame
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    global.set $frame-next
  )

  (func $helper-resume (param $frame i32)
    ;; [guest-async-parent-resume]
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    i32.const 2
    i32.ne
    if
      ;; [guest-async-child-drop]
      local.get $frame
      i32.const 4
      i32.add
      i32.load
      i32.const 4
      i32.shr_u
      call $subtask-drop
    end
    local.get $frame
    i32.load
    call $waitable-set-drop
    i32.const 0
    call $context-set-0
    local.get $frame
    call $frame-free
    call $task-return-run
  )

  (func $helper (param $frame i32) (result i32) (local $subtask i32)
    ;; [guest-async-child]
    call $host-work
    local.set $subtask
    local.get $frame
    i32.const 4
    i32.add
    local.get $subtask
    i32.store
    local.get $subtask
    i32.const 2
    i32.eq
    if (result i32)
      local.get $frame
      call $helper-resume
      i32.const 0
    else
      local.get $subtask
      i32.const 4
      i32.shr_u
      local.get $frame
      i32.load
      call $waitable-join
      local.get $frame
      i32.load
      i32.const 4
      i32.shl
      i32.const 2
      i32.or
    end
  )

  (func (export "[async-lift]run") (type $async-run) (local $frame i32)
    call $frame-alloc
    local.set $frame
    local.get $frame
    call $context-set-0
    local.get $frame
    call $waitable-set-new
    i32.store
    local.get $frame
    i32.const 4
    i32.add
    i32.const 2
    i32.store
    local.get $frame
    i32.const 8
    i32.add
    i32.const 1
    i32.store
    local.get $frame
    call $helper
  )

  (func (export "[callback][async-lift]run") (type $async-callback)
    (local $frame i32)
    call $context-get-0
    local.set $frame
    local.get 0
    i32.const 1
    i32.eq
    if (result i32)
      local.get 2
      i32.const 2
      i32.eq
      if (result i32)
        local.get $frame
        call $helper-resume
        i32.const 0
      else
        unreachable
        i32.const 0
      end
    else
      unreachable
      i32.const 0
    end
  )

  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable
  )
  (func (export "_initialize"))
)
