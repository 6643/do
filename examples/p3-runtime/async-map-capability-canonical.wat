;; Private async map capability probe. The map input is a canonical pair-list
;; view for the call only; the host must copy it before its Future can suspend.
(module
  (type $async-submit (func (param i32 i32 i32) (result i32)))
  (type $task-noargs (func))
  (type $task-return-u32 (func (param i32)))
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

  (import "demo:map-async-probe/api@0.1.0" "[async-lower]submit"
    (func $submit (type $async-submit)))
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
  (import "[export]$root" "[task-return]run" (func $task-return-run (type $task-return-u32)))

  (memory (export "memory") 1)
  (global $frame-next (mut i32) (i32.const 2048))

  ;; Frame layout: waitable @0, encoded subtask @4, u32 result-area @8,
  ;; lifecycle state @12. The input pair-list lives at 1024 and is never
  ;; retained after the submit call returns.
  (func $frame-alloc (result i32) (local $frame i32)
    global.get $frame-next
    local.tee $frame
    i32.const 16
    i32.add
    global.set $frame-next
    local.get $frame
  )

  (func $frame-free (param $frame i32)
    ;; [async-map-frame-free]
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
    ;; [async-map-drop]
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
    ;; [async-map-cancel]
    local.get $encoded
    i32.const 4
    i32.shr_u
    call $subtask-cancel
    local.set $ignored
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

  (func $cleanup (param $frame i32) (param $cancelled i32) (param $result i32)
    local.get $cancelled
    if
      local.get $frame
      call $cancel-subtask
    else
      local.get $frame
      call $drop-subtask
    end
    local.get $frame
    i32.load
    call $waitable-set-drop
    i32.const 0
    call $context-set-0
    local.get $frame
    call $frame-free
    local.get $cancelled
    if
      call $task-cancel
    else
      local.get $result
      call $task-return-run
    end
  )

  (func $finish (param $frame i32)
    (local $result i32)
    ;; [async-map-result-area]
    local.get $frame
    i32.const 8
    i32.add
    i32.load
    local.set $result
    ;; [async-map-complete]
    local.get $frame
    i32.const 0
    local.get $result
    call $cleanup
  )

  (func $wait-on-submit (param $frame i32) (result i32)
    ;; [async-map-pending]
    local.get $frame
    i32.const 4
    i32.add
    i32.load
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
  )

  (func $start-submit (param $frame i32) (result i32) (local $subtask i32)
    ;; [async-map-input-copy]
    i32.const 1024
    i32.const 2
    local.get $frame
    i32.const 8
    i32.add
    call $submit
    local.set $subtask
    local.get $frame
    i32.const 4
    i32.add
    local.get $subtask
    i32.store
    ;; [async-map-input-overwrite]
    i32.const 1024
    i32.const 100
    i32.store
    i32.const 1028
    i32.const 1000
    i32.store
    i32.const 1032
    i32.const 101
    i32.store
    i32.const 1036
    i32.const 1001
    i32.store
    local.get $subtask
    i32.const 2
    i32.eq
    if (result i32)
      local.get $frame
      call $finish
      i32.const 0
    else
      local.get $frame
      call $wait-on-submit
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
    i32.const 0
    i32.store
    local.get $frame
    i32.const 12
    i32.add
    i32.const 1
    i32.store
    ;; [async-map-input-copy] pair-list entries are [7,70] and [9,90].
    i32.const 1024
    i32.const 7
    i32.store
    i32.const 1028
    i32.const 70
    i32.store
    i32.const 1032
    i32.const 9
    i32.store
    i32.const 1036
    i32.const 90
    i32.store
    local.get $frame
    call $start-submit
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
        call $finish
        i32.const 0
      else
        unreachable
        i32.const 0
      end
    else
      local.get 0
      i32.const 2
      i32.eq
      if (result i32)
        local.get $frame
        i32.const 1
        i32.const 0
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
