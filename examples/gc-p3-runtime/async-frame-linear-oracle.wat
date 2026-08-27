;; Linear-memory oracle for the bounded two-await P3 frame contract.
;; This is a test-only backend-neutral comparison artifact. It has the same
;; imports, callback state transitions, frame slots, and WIT surface as the
;; generated GC frame path, but keeps the frame in linear memory.
(module
  (type $async-lower (func (param i64) (result i32)))
  (type $task-return (func))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $async-run (func (param i64) (result i32)))
  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "wasi:clocks/monotonic-clock@0.3.0" "[async-lower]wait-for"
    (func $first-host-call (type $async-lower)))
  (import "wasi:clocks/monotonic-clock@0.3.0" "[async-lower]wait-until"
    (func $second-host-call (type $async-lower)))
  (import "$root" "[waitable-set-new]"
    (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-join]"
    (func $waitable-join (type $waitable-join)))
  (import "$root" "[context-get-0]"
    (func $context-get-0 (result i32)))
  (import "$root" "[context-set-0]"
    (func $context-set-0 (param i32)))
  (import "[export]$root" "[task-return]run"
    (func $task-return (type $task-return)))

  (memory (export "memory") 1)
  (global $frame-next (mut i32) (i32.const 1024))

  ;; Frame layout: state@0, waitable-set@4, cleanup-flags@8,
  ;; completion-value@12, deadline@16, first_deadline@24,
  ;; second_deadline@32. The last two slots make the retained-value
  ;; contract explicit even though this bounded body only resumes deadline.
  (func $frame-alloc (result i32)
    (local $frame i32)
    (local $end i32)
    global.get $frame-next
    local.tee $frame
    i32.const 40
    i32.add
    local.tee $end
    global.set $frame-next
    local.get $end
    memory.size
    i32.const 16
    i32.shl
    i32.gt_u
    if unreachable end
    local.get $frame
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    i32.const 0
    i32.store)

  (func (export "[async-lift]run") (type $async-run)
    (local $frame i32)
    (local $waitable-set i32)
    (local $subtask i32)
    call $waitable-set-new
    local.set $waitable-set
    call $frame-alloc
    local.set $frame

    local.get $frame
    i32.const 1
    i32.store offset=0
    local.get $frame
    local.get $waitable-set
    i32.store offset=4
    local.get $frame
    i32.const 0
    i32.store offset=8
    local.get $frame
    i32.const 0
    i32.store offset=12
    local.get $frame
    local.get 0
    i64.store offset=16
    local.get $frame
    local.get 0
    i64.store offset=24
    local.get $frame
    i64.const 0
    i64.store offset=32

    local.get $frame
    call $context-set-0
    local.get 0
    call $first-host-call
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

  (func (export "[callback][async-lift]run") (type $async-run-callback)
    (local $frame i32)
    (local $state i32)
    (local $subtask i32)
    call $context-get-0
    local.set $frame
    local.get 0
    i32.const 1
    i32.eq
    local.get 2
    i32.const 2
    i32.eq
    i32.and
    if (result i32)
      local.get $frame
      i32.load offset=0
      local.tee $state
      i32.const 1
      i32.eq
      if (result i32)
        local.get $frame
        i32.const 2
        i32.store offset=0
        local.get $frame
        i64.load offset=16
        call $second-host-call
        local.set $subtask
        local.get $subtask
        i32.const 4
        i32.shr_u
        local.get $frame
        i32.load offset=4
        call $waitable-join
        local.get $frame
        i32.load offset=4
        i32.const 4
        i32.shl
        i32.const 2
        i32.or
      else
        local.get $state
        i32.const 2
        i32.ne
        if unreachable end
        i32.const 0
        call $context-set-0
        local.get $frame
        call $frame-free
        call $task-return
        i32.const 0
      end
    else
      local.get $frame
      i32.load offset=4
      i32.const 4
      i32.shl
      i32.const 2
      i32.or
    end
  )

  ;; No canonical payload is used by this unit; the export is present because
  ;; Component assembly requires the standard guest realloc surface.
  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
  (func (export "_initialize"))
)
