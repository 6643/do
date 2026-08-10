(module
  ;; Canonical async imports measured from wasm-tools 1.255.0 for
  ;; descriptor.metadata-hash-at.
  (type $method (func (param i32 i32 i32 i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $noargs (func))
  (type $root-new (func (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-poll (func (param i32 i32) (result i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $async-run (func (param i32 i32 i32 i32) (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  ;; [metadata-hash-at-task-return-layout]
  (type $task-return-metadata-hash-at (func (param i32 i64 i64)))

  ;; [metadata-hash-at-call] descriptor, path-flags, path pointer, length,
  ;; and result-area pointer.
  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16"
    "[async-lower][method]descriptor.metadata-hash-at"
    (func $metadata-hash-at (type $method)))
  ;; [descriptor-drop] the owned descriptor is released exactly once.
  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16"
    "[resource-drop]descriptor"
    (func $descriptor-drop (type $resource-drop)))

  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $noargs)))
  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $noargs)))
  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $noargs)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $root-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $root-poll)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $root-poll)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $resource-drop)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $root-join)))
  (import "$root" "[thread-yield]" (func $thread-yield (type $root-new)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $resource-drop)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $root-new)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $resource-drop)))
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16"
    "[task-return]run" (func $task-return-run (type $task-return-metadata-hash-at)))

  (memory $memory 1)
  (global $frame-next (mut i32) (i32.const 1024))
  (global $heap-next (mut i32) (i32.const 65536))

  ;; Frame layout:
  ;;   0 waitable:i32, 4 descriptor:i32, 8 path-flags:i32,
  ;;   12 path-ptr:i32, 16 path-len:i32, 20 status:i32,
  ;;   24 result-tag:u8, 32 lower:u64, 40 upper:u64,
  ;;   48 callback-subtask:i32.
  ;; [metadata-hash-at-result-area] tag is frame+24 and the aligned record
  ;; payload begins at frame+32. Err uses the first payload slot.

  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 56
    i32.add
    global.set $frame-next
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    drop
  )

  ;; [metadata-hash-at-pending] join the live subtask with the frame waitable.
  (func $wait-on-metadata-hash-at (param $frame i32) (result i32)
    local.get $frame
    i32.const 20
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

  ;; [metadata-hash-at-ready] read both u64 words before cleanup.
  ;; [metadata-hash-at-error] map the error code into the first flat word.
  (func $finish (param $frame i32) (result i32)
    (local $tag i32)
    (local $lower i64)
    (local $upper i64)
    (local $subtask i32)
    local.get $frame
    i32.const 24
    i32.add
    i32.load8_u
    local.set $tag
    local.get $tag
    i32.eqz
    if
      local.get $frame
      i32.const 32
      i32.add
      i64.load
      local.set $lower
      local.get $frame
      i32.const 40
      i32.add
      i64.load
      local.set $upper
    else
      local.get $frame
      i32.const 32
      i32.add
      i32.load8_u
      i64.extend_i32_u
      local.set $lower
      i64.const 0
      local.set $upper
    end
    local.get $frame
    i32.const 48
    i32.add
    i32.load
    local.set $subtask
    local.get $subtask
    i32.eqz
    if
    else
      local.get $subtask
      call $subtask-drop
    end
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    call $descriptor-drop
    local.get $frame
    i32.load
    call $waitable-set-drop
    i32.const 0
    call $context-set-0
    local.get $tag
    local.get $lower
    local.get $upper
    call $task-return-run
    local.get $frame
    call $frame-free
    i32.const 0
  )

  (func $start-metadata-hash-at (param $frame i32) (result i32)
    (local $status i32)
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    local.get $frame
    i32.const 8
    i32.add
    i32.load
    local.get $frame
    i32.const 12
    i32.add
    i32.load
    local.get $frame
    i32.const 16
    i32.add
    i32.load
    local.get $frame
    i32.const 24
    i32.add
    call $metadata-hash-at
    local.set $status
    local.get $frame
    i32.const 20
    i32.add
    local.get $status
    i32.store
    local.get $status
    i32.const 2
    i32.eq
    if (result i32)
      local.get $frame
      call $finish
    else
      local.get $frame
      call $wait-on-metadata-hash-at
    end
  )

  (func $run (type $async-run)
    (local $frame i32)
    call $frame-alloc
    local.tee $frame
    call $context-set-0
    local.get $frame
    call $waitable-set-new
    i32.store
    local.get $frame
    i32.const 4
    i32.add
    local.get 0
    i32.store
    local.get $frame
    i32.const 8
    i32.add
    local.get 1
    i32.store
    local.get $frame
    i32.const 12
    i32.add
    local.get 2
    i32.store
    local.get $frame
    i32.const 16
    i32.add
    local.get 3
    i32.store
    local.get $frame
    i32.const 20
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 24
    i32.add
    i32.const 0
    i32.store8
    local.get $frame
    i32.const 48
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    call $start-metadata-hash-at
  )

  (func $callback (type $async-callback)
    (local $frame i32)
    call $context-get-0
    local.set $frame
    local.get 0
    i32.const 1
    i32.eq
    if (result i32)
      local.get $frame
      i32.const 48
      i32.add
      local.get 1
      i32.store
      local.get 2
      i32.const 2
      i32.eq
      if (result i32)
        local.get $frame
        call $finish
      else
        unreachable
      end
    else
      local.get $frame
      call $wait-on-metadata-hash-at
    end
  )

  (func $cabi-realloc (type $cabi-realloc)
    (local $ptr i32)
    global.get $heap-next
    local.set $ptr
    local.get $ptr
    local.get 3
    i32.add
    global.set $heap-next
    local.get $ptr
  )

  (func $_initialize (type $noargs))

  (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run"
    (func $run))
  (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run"
    (func $callback))
  (export "memory" (memory $memory))
  (export "cabi_realloc" (func $cabi-realloc))
  (export "_initialize" (func $_initialize))
)
