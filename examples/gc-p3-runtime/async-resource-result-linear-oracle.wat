;; Linear-memory oracle for the bounded async resource Result contract.
;; This test-only component core has the same P3 async-lift surface as the
;; generated GC route. Its frame and result area are kept in linear memory so
;; host observations can be compared without reusing the GC implementation.
(module
  (type $async-lower-send (func (param i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $task-return (func (param i32 i32)))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-set-wait (func (param i32 i32) (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $async-run (func (param i32) (result i32)))
  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (type $initialize (func))

  (import "do:resource-probe/http@0.1.0" "[async-lower]send"
    (func $send (type $async-lower-send)))
  (import "do:resource-probe/http@0.1.0" "[resource-drop]request"
    (func $drop-request (type $resource-drop)))
  (import "do:resource-probe/http@0.1.0" "[resource-drop]response"
    (func $drop-response (type $resource-drop)))
  (import "$root" "[waitable-set-new]"
    (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-set-wait]"
    (func $waitable-set-wait (type $waitable-set-wait)))
  (import "$root" "[waitable-join]"
    (func $waitable-join (type $waitable-join)))
  (import "$root" "[context-get-0]"
    (func $context-get-0 (type $context-get)))
  (import "$root" "[context-set-0]"
    (func $context-set-0 (type $context-set)))
  (import "[export]$root" "[task-return]run"
    (func $task-return (type $task-return)))

  (memory (export "memory") 1)
  (global $frame-next (mut i32) (i32.const 1024))
  (global $heap-next (mut i32) (i32.const 65536))

  ;; Frame layout: state@0, waitable-set@4, result-area@8, subtask@12.
  (func $frame-alloc (result i32)
    (local $frame i32)
    (local $end i32)
    global.get $frame-next
    local.tee $frame
    i32.const 16
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
    i32.store
    local.get $frame
    i32.const 4
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 8
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 12
    i32.add
    i32.const 0
    i32.store
  )

  ;; The generated GC route indexes one eight-byte result area by frame handle.
  ;; Preserve that ABI shape while storing the linear frame separately.
  (func $result-buffer-for-handle (param $handle i32) (result i32)
    local.get $handle
    i32.const 3
    i32.shl
  )

  (func (export "[async-lift]run") (type $async-run)
    (local $frame i32)
    (local $waitable-set i32)
    (local $result-area i32)
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
    local.get $frame
    call $result-buffer-for-handle
    local.tee $result-area
    i32.store offset=8
    local.get $frame
    i32.const 0
    i32.store offset=12
    local.get $frame
    call $context-set-0
    local.get 0
    local.get $result-area
    call $send
    local.tee $subtask
    local.get $frame
    i32.store offset=12
    local.get $subtask
    i32.const 2
    i32.eq
    if (result i32)
      i32.const 0
      call $context-set-0
      local.get $result-area
      i32.load
      local.get $result-area
      i32.const 4
      i32.add
      i32.load
      call $task-return
      local.get $frame
      call $frame-free
      i32.const 0
    else
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
    end
  )

  (func (export "[callback][async-lift]run") (type $async-run-callback)
    (local $frame i32)
    (local $result-area i32)
    call $context-get-0
    local.set $frame
    local.get $frame
    i32.load offset=8
    local.set $result-area
    local.get 0
    i32.const 1
    i32.eq
    local.get 2
    i32.const 2
    i32.eq
    i32.and
    if (result i32)
      local.get $result-area
      i32.load
      local.get $result-area
      i32.const 4
      i32.add
      i32.load
      call $task-return
      i32.const 0
      call $context-set-0
      local.get $frame
      call $frame-free
      i32.const 0
    else
      local.get 0
      i32.const 1
      i32.eq
      local.get 2
      i32.const 1
      i32.eq
      i32.and
      if (result i32)
        i32.const 0
        local.get $result-area
        i32.store
        local.get $result-area
        i32.const 4
        i32.add
        local.get 2
        i32.store
        i32.const 0
        call $context-set-0
        local.get $result-area
        i32.load
        local.get $result-area
        i32.const 4
        i32.add
        i32.load
        call $task-return
        local.get $frame
        call $frame-free
        i32.const 0
      else
        local.get $frame
        i32.load offset=4
        i32.const 4
        i32.shl
        i32.const 2
        i32.or
      end
    end
  )

  (func (export "cabi_realloc") (type $cabi-realloc)
    (local $ptr i32)
    (local $end i32)
    global.get $heap-next
    local.set $ptr
    local.get $ptr
    local.get 3
    i32.add
    local.tee $end
    global.set $heap-next
    local.get $end
    memory.size
    i32.const 16
    i32.shl
    i32.gt_u
    if
      local.get $end
      i32.const 65535
      i32.add
      i32.const 16
      i32.shr_u
      memory.size
      i32.sub
      memory.grow
      i32.const -1
      i32.eq
      if unreachable end
    end
    local.get $ptr
  )

  (func (export "_initialize") (type $initialize))
)
