(module
  (type $async-lower-send (func (param i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $task-return (func))
  (type $root-noargs (func))
  (type $root-new (func (result i32)))
  (type $root-wait (func (param i32 i32) (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-cancel (func (param i32) (result i32)))
  (type $async-run (func (param i32) (result i32)))
  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
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
  (import "[export]$root" "[task-return]cancel" (func $task-return (type $task-return)))

  (memory (export "memory") 1)
  (global $allocated-ptr (mut i32) (i32.const 0))
  (global $allocation-count (mut i32) (i32.const 0))
  (global $release-count (mut i32) (i32.const 0))

  (func $cabi-realloc (export "cabi_realloc") (type $cabi-realloc)
    (param $old i32)
    (param $old-size i32)
    (param $align i32)
    (param $size i32)
    (result i32)
    local.get $old
    i32.eqz
    if (result i32)
      local.get $old-size
      i32.eqz
      if else unreachable end
      local.get $align
      i32.const 1
      i32.ne
      if unreachable end
      local.get $size
      i32.const 12
      i32.ne
      if unreachable end
      global.get $allocation-count
      i32.eqz
      if else unreachable end
      i32.const 1024
      global.set $allocated-ptr
      i32.const 1
      global.set $allocation-count
      i32.const 1024
    else
      local.get $old
      global.get $allocated-ptr
      i32.ne
      if unreachable end
      local.get $old-size
      i32.const 12
      i32.ne
      if unreachable end
      local.get $align
      i32.const 1
      i32.ne
      if unreachable end
      local.get $size
      i32.eqz
      if else unreachable end
      global.get $allocation-count
      i32.const 1
      i32.ne
      if unreachable end
      global.get $release-count
      i32.eqz
      if else unreachable end
      i32.const 1
      global.set $release-count
      local.get $old
    end)

  (func (export "[async-lift]cancel") (type $async-run)
    (local $subtask i32)
    (local $string-ptr i32)
    local.get 0
    ;; The result area matches the fixed private cancellation scratch range.
    i32.const 64
    call $send
    local.set $subtask
    local.get $subtask
    i32.const 2
    i32.ne
    if unreachable end

    ;; Err(HTTP-request-header-size(Some(field-size-payload))).
    i32.const 64
    i32.load
    i32.const 1
    i32.ne
    if unreachable end
    i32.const 72
    i32.load
    i32.const 22
    i32.ne
    if unreachable end
    i32.const 80
    i32.load
    i32.const 1
    i32.ne
    if unreachable end

    ;; field-name is Some("content-type").
    i32.const 84
    i32.load
    i32.const 1
    i32.ne
    if unreachable end
    i32.const 88
    i32.load
    local.tee $string-ptr
    global.get $allocated-ptr
    i32.ne
    if unreachable end
    i32.const 92
    i32.load
    i32.const 12
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.load8_u
    i32.const 99
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 1
    i32.add
    i32.load8_u
    i32.const 111
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 2
    i32.add
    i32.load8_u
    i32.const 110
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 3
    i32.add
    i32.load8_u
    i32.const 116
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 4
    i32.add
    i32.load8_u
    i32.const 101
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 5
    i32.add
    i32.load8_u
    i32.const 110
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 6
    i32.add
    i32.load8_u
    i32.const 116
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 7
    i32.add
    i32.load8_u
    i32.const 45
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 8
    i32.add
    i32.load8_u
    i32.const 116
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 9
    i32.add
    i32.load8_u
    i32.const 121
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 10
    i32.add
    i32.load8_u
    i32.const 112
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 11
    i32.add
    i32.load8_u
    i32.const 101
    i32.ne
    if unreachable end
    local.get $string-ptr
    i32.const 12
    i32.const 1
    i32.const 0
    call $cabi-realloc
    drop

    ;; field-size is Some(42).
    i32.const 96
    i32.load
    i32.const 1
    i32.ne
    if unreachable end
    i32.const 100
    i32.load
    i32.const 42
    i32.ne
    if unreachable end

    global.get $allocation-count
    i32.const 1
    i32.ne
    if unreachable end
    global.get $release-count
    i32.const 1
    i32.ne
    if unreachable end
    call $task-return
    i32.const 0)

  (func (export "[callback][async-lift]cancel") (type $async-run-callback)
    unreachable)
  (func (export "_initialize") (type $root-noargs))
)
