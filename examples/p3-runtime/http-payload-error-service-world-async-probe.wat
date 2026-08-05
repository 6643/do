(module
  (type $async-lower-send (func (param i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $async-handler (func (param i32) (result i32)))
  (type $async-handler-callback (func (param i32 i32 i32) (result i32)))
  (type $root-noargs (func))
  (type $root-new (func (result i32)))
  (type $root-wait (func (param i32 i32) (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-cancel (func (param i32) (result i32)))
  (type $task-return (func (param i32 i32 i32 i64 i32 i32 i32 i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (type $async-frame (struct
    (field $state (mut i32))
    (field $waitable-set (mut i32))
    (field $cleanup-flags (mut i32))
    (field $completion-value (mut i32))
    (field $slot-result-ptr (mut i32))))

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
  (import "[export]wasi:http/handler@0.3.0-rc-2025-09-16" "[task-return]handle"
    (func $task-return (type $task-return)))

  (memory (export "memory") 2)
  (table $async-frames 0 (ref null $async-frame))
  (func $frame-alloc (param $frame (ref $async-frame)) (result i32)
    (local $handle i32)
    local.get $frame
    i32.const 1
    table.grow $async-frames
    local.set $handle
    local.get $handle
    local.get $frame
    table.set $async-frames
    local.get $handle)
  (global $heap-next (mut i32) (i32.const 1024))
  (func (export "[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle")
    (type $async-handler)
    (param $request i32)
    (result i32)
    (local $subtask i32)
    (local $frame i32)
    (local $frame-ref (ref $async-frame))
    i32.const 1
    call $waitable-set-new
    i32.const 0
    i32.const 0
    i32.const 0
    struct.new $async-frame
    call $frame-alloc
    local.tee $frame
    call $context-set-0
    local.get $frame
    table.get $async-frames
    ref.as_non_null
    local.set $frame-ref
    local.get $frame-ref
    i32.const 1024
    struct.set $async-frame $slot-result-ptr
    local.get $request
    local.get $frame-ref
    struct.get $async-frame $slot-result-ptr
    call $send
    local.set $subtask
    local.get $subtask
    i32.const 4
    i32.shr_u
    local.get $frame-ref
    struct.get $async-frame $waitable-set
    call $waitable-join
    local.get $frame-ref
    struct.get $async-frame $waitable-set
    i32.const 4
    i32.shl
    i32.const 2
    i32.or)
  (func (export "[callback][async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle")
    (type $async-handler-callback)
    (param $event i32)
    (param $index i32)
    (param $payload i32)
    (result i32)
    (local $frame i32)
    (local $frame-ref (ref $async-frame))
    (local $result-ptr i32)
    local.get $event
    i32.const 1
    i32.eq
    local.get $payload
    i32.const 2
    i32.eq
    i32.and
    if (result i32)
      call $context-get-0
      local.set $frame
      local.get $frame
      table.get $async-frames
      ref.as_non_null
      local.set $frame-ref
      local.get $frame-ref
      struct.get $async-frame $slot-result-ptr
      local.set $result-ptr
      i32.const 1
      local.get $result-ptr
      i32.const 8
      i32.add
      i32.load
      local.get $result-ptr
      i32.const 16
      i32.add
      i32.load
      local.get $result-ptr
      i32.const 20
      i32.add
      i32.load
      i64.extend_i32_u
      local.get $result-ptr
      i32.const 24
      i32.add
      i32.load
      i32.const 0
      i32.const 0
      i32.const 0
      call $task-return
      i32.const 0
    else
      unreachable
    end)
  (func (export "cabi_realloc") (type $cabi-realloc)
    (param $old i32)
    (param $old-size i32)
    (param $align i32)
    (param $size i32)
    (result i32)
    (local $ptr i32)
    global.get $heap-next
    local.set $ptr
    local.get $ptr
    local.get $size
    i32.add
    global.set $heap-next
    local.get $ptr)
  (func (export "_initialize") (type $root-noargs))
)
