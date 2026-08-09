;; Canonical Core module for the private async host scalar-argument probe.
;; The helper is a root-owned continuation. The only task-return endpoint is
;; the exported root operation; helper state is kept in the root frame.
(module
  (type $async-lower-work (func (param i32) (result i32)))
  (type $task-noargs (func))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $waitable-poll (func (param i32 i32) (result i32)))
  (type $waitable-drop (func (param i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $subtask-drop (func (param i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $async-run (func (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "do:async-call-arg-probe/host@0.1.0" "[async-lower]work"
    (func $host-work (type $async-lower-work)))
  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-noargs)))
  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $task-noargs)))
  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $task-noargs)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-poll)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-poll)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[thread-yield]" (func $thread-yield (type $waitable-set-new)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $subtask-drop)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
  (import "[export]$root" "[task-return]run" (func $task-return-run (type $task-noargs)))

  (memory (export "memory") 1)
  (global $frame-next (mut i32) (i32.const 1024))

  ;; Frame layout: waitable set @0, encoded host subtask @4, helper state @8,
  ;; one u32 argument slot @12. The fixed frame is 20 bytes, 4-byte aligned.
  (func $frame-alloc (result i32) (local $frame i32)
    global.get $frame-next
    local.tee $frame
    i32.const 20
    i32.add
    global.set $frame-next
    local.get $frame
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    global.set $frame-next
  )

  (func $drop-subtask (param $frame i32) (local $encoded i32)
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    local.tee $encoded
    i32.const 2
    i32.eq
    if
      return
    end
    ;; [guest-async-child-drop]
    local.get $encoded
    i32.const 4
    i32.shr_u
    call $subtask-drop
    local.get $frame
    i32.const 4
    i32.add
    i32.const 0
    i32.store
  )

  (func $cancel-subtask (param $frame i32) (local $encoded i32) (local $ignored i32)
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    local.tee $encoded
    i32.const 2
    i32.eq
    if
      return
    end
    local.get $encoded
    i32.const 4
    i32.shr_u
    call $subtask-cancel
    local.set $ignored
    ;; [guest-async-child-drop]
    local.get $encoded
    i32.const 4
    i32.shr_u
    call $subtask-drop
    local.get $frame
    i32.const 4
    i32.add
    i32.const 0
    i32.store
  )

  ;; Cleanup is shared by ready/pending terminal completion and cancellation.
  ;; The caller passes 1 only for external cancellation.
  (func $cleanup (param $frame i32) (param $cancelled i32)
    local.get $cancelled
    if
      local.get $frame
      call $cancel-subtask
    else
      local.get $frame
      call $drop-subtask
    end
    ;; [guest-async-waitable-drop]
    local.get $frame
    i32.load
    call $waitable-set-drop
    ;; [guest-async-context-clear]
    i32.const 0
    call $context-set-0
    local.get $frame
    call $frame-free
    ;; [guest-async-frame-free]
    local.get $cancelled
    if
      call $task-cancel
    else
      call $task-return-run
    end
  )

  (func $helper-resume (param $frame i32)
    ;; [guest-async-parent-resume]
    ;; [guest-async-arg-load]
    local.get $frame
    i32.const 12
    i32.add
    i32.load
    drop
    local.get $frame
    i32.const 0
    call $cleanup
  )

  (func $helper (param $frame i32) (param $value i32) (result i32) (local $subtask i32)
    ;; [guest-async-arg-store]
    local.get $frame
    i32.const 12
    i32.add
    local.get $value
    i32.store
    ;; [guest-async-host-arg]
    local.get $value
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
    ;; Fixed source shape: run starts helper(7).
    local.get $frame
    i32.const 7
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
        ;; [guest-async-parent-resume]
        local.get $frame
        call $helper-resume
        i32.const 0
      else
        local.get $frame
        i32.const 1
        call $cleanup
        i32.const 0
      end
    else
      local.get 0
      i32.const 2
      i32.eq
      if (result i32)
        local.get $frame
        i32.const 1
        call $cleanup
        i32.const 0
      else
        unreachable
        i32.const 0
      end
    end
  )

  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable
  )
  (func (export "_initialize"))
)
