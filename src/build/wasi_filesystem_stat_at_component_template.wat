(module
  ;; Canonical async imports and the flattened task-return signature are
  ;; measured from wasm-tools 1.255.0.  This probe intentionally keeps the
  ;; implementation small: the host method result is copied into a fixed
  ;; frame, then returned through the Component async callback contract.
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
  ;; [stat-at-task-return-layout]
  ;; result tag, descriptor-type, link-count, size, then three
  ;; option<datetime> triples (presence, seconds, nanoseconds).
  (type $task-return-stat-at (func (param i32 i32 i64 i64 i32 i64 i32 i32 i64 i32 i32 i64 i32)))

  ;; [stat-at-call] descriptor, path-flags, UTF-8 path pointer/length, and
  ;; result-area pointer are the measured method arguments.
  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16"
    "[async-lower][method]descriptor.stat-at"
    (func $stat-at (type $method)))
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
    "[task-return]run" (func $task-return-run (type $task-return-stat-at)))

  ;; One extra page keeps the canonical UTF-8 path allocation below the
  ;; linear-memory limit while preserving the measured frame layout.
  (memory $memory 2)
  (global $frame-next (mut i32) (i32.const 1024))
  (global $heap-next (mut i32) (i32.const 65536))

  ;; Frame layout (all offsets are part of the probe contract):
  ;;   0 waitable:i32, 4 descriptor:i32, 8 path-flags:i32,
  ;;   12 path-ptr:i32, 16 path-len:i32, 20 status:i32,
  ;;   24 result-tag:u8, 32 descriptor-type:u8, 40 link-count:u64,
  ;;   48 size:u64, 56/64/72 access option,
  ;;   80/88/96 modification option, 104/112/120 change option,
  ;;   132 callback-subtask-handle:i32.
  ;; [stat-at-result-area] the async-lower return pointer uses the canonical
  ;; result<descriptor-stat, error-code> memory layout beginning at offset 24:
  ;;   result tag 24, payload 32, descriptor type 32, link-count 40, size 48,
  ;;   access option 56/64/72, modification 80/88/96, change 104/112/120.
  ;; [stat-at-option-presence] option discriminants are canonical u8 values;
  ;; datetime payloads are aligned as u64 seconds followed by u32 nanoseconds.
  ;; [stat-at-path-copy] the lowered UTF-8 pointer/length are retained in the
  ;; frame until the host method completes; the eventual emitter owns the copy.

  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 144
    i32.add
    global.set $frame-next
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    drop
  )

  ;; [stat-at-ready] the successful result is read from the canonical return area
  ;; and lowered to the measured flat task-return signature.
  ;; [stat-at-error] the error discriminant and payload are read from the same
  ;; canonical result area; no record payload is fabricated.

  (func $wait-on-stat-at (param $frame i32) (result i32)
    ;; [stat-at-pending] join the live subtask with the frame waitable.
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

  (func $finish (param $frame i32) (result i32)
    (local $tag i32)
    (local $dtype i32)
    (local $link i64)
    (local $size i64)
    (local $access-present i32)
    (local $access-seconds i64)
    (local $access-nanos i32)
    (local $mod-present i32)
    (local $mod-seconds i64)
    (local $mod-nanos i32)
    (local $change-present i32)
    (local $change-seconds i64)
    (local $change-nanos i32)
    (local $subtask i32)
    ;; [stat-at-ready] canonical result<descriptor-stat, error-code> has an
    ;; eight-byte-aligned Ok payload. Read all fields before cleanup.
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
      i32.load8_u
      local.set $dtype
      local.get $frame
      i32.const 40
      i32.add
      i64.load
      local.set $link
      local.get $frame
      i32.const 48
      i32.add
      i64.load
      local.set $size
      local.get $frame
      i32.const 56
      i32.add
      i32.load8_u
      local.set $access-present
      local.get $frame
      i32.const 64
      i32.add
      i64.load
      local.set $access-seconds
      local.get $frame
      i32.const 72
      i32.add
      i32.load
      local.set $access-nanos
      local.get $frame
      i32.const 80
      i32.add
      i32.load8_u
      local.set $mod-present
      local.get $frame
      i32.const 88
      i32.add
      i64.load
      local.set $mod-seconds
      local.get $frame
      i32.const 96
      i32.add
      i32.load
      local.set $mod-nanos
      local.get $frame
      i32.const 104
      i32.add
      i32.load8_u
      local.set $change-present
      local.get $frame
      i32.const 112
      i32.add
      i64.load
      local.set $change-seconds
      local.get $frame
      i32.const 120
      i32.add
      i32.load
      local.set $change-nanos
    else
      ;; [stat-at-error] the Err payload is the canonical u8 error discriminant.
      local.get $frame
      i32.const 32
      i32.add
      i32.load8_u
      local.set $dtype
    end
    local.get $frame
    i32.const 132
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
    local.get $dtype
    local.get $link
    local.get $size
    local.get $access-present
    local.get $access-seconds
    local.get $access-nanos
    local.get $mod-present
    local.get $mod-seconds
    local.get $mod-nanos
    local.get $change-present
    local.get $change-seconds
    local.get $change-nanos
    call $task-return-run
    local.get $frame
    call $frame-free
    i32.const 0
  )

  (func $start-stat-at (param $frame i32) (result i32)
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
    call $stat-at
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
      call $wait-on-stat-at
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
    i32.const 132
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    call $start-stat-at
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
      i32.const 132
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
      call $wait-on-stat-at
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
