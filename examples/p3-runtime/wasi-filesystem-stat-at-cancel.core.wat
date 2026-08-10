(module
  ;; Cancellation variant of the wasm-tools 1.255.0 stat layout probe.
  (type $method (func (param i32 i32 i32 i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $noargs (func))
  (type $root-new (func (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-poll (func (param i32 i32) (result i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $async-run (func (param i32 i32 i32 i32) (result i32)))
  (type $async-cancel (func (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  ;; [stat-at-task-return-layout]
  (type $task-return-stat-at (func (param i32 i32 i64 i64 i32 i64 i32 i32 i64 i32 i32 i64 i32)))

  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16"
    "[async-lower][method]descriptor.stat-at" (func $stat-at (type $method)))
  ;; [descriptor-drop]
  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16"
    "[resource-drop]descriptor" (func $descriptor-drop (type $resource-drop)))
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
  ;; [subtask-cancel]
  (import "$root" "[async-lower][subtask-cancel]"
    (func $subtask-cancel (type $subtask-cancel)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $root-new)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $resource-drop)))
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16"
    "[task-return]run" (func $task-return-run (type $task-return-stat-at)))
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16"
    "[task-return]cancel" (func $task-return-cancel (type $noargs)))

  ;; One extra page keeps the canonical UTF-8 path allocation below the
  ;; linear-memory limit while preserving the measured frame layout.
  (memory $memory 2)
  (global $frame-next (mut i32) (i32.const 1024))
  (global $heap-next (mut i32) (i32.const 65536))
  (global $run-frame (mut i32) (i32.const 0))

  ;; Frame layout (all offsets are part of the probe contract):
  ;;   0 waitable:i32, 4 descriptor:i32, 8 path-flags:i32,
  ;;   12 path-ptr:i32, 16 path-len:i32, 20 status:i32,
  ;;   24 result-tag:u8, 32 descriptor-type:u8, 40 link-count:u64,
  ;;   48 size:u64, 56/64/72 access option,
  ;;   80/88/96 modification option, 104/112/120 change option,
  ;;   132 callback-subtask-handle:i32.
  ;; [stat-at-result-area]
  ;; [stat-at-option-presence]
  ;; [stat-at-path-copy] the lowered UTF-8 pointer/length are retained in the
  ;; frame until completion or cancellation; the eventual emitter owns the copy.
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

  ;; [stat-at-ready] deterministic regular-file payload for a completed call.
  (func $write-ready (param $frame i32)
    local.get $frame i32.const 24 i32.add i32.const 0 i32.store8
    local.get $frame i32.const 32 i32.add i32.const 6 i32.store8
    local.get $frame i32.const 40 i32.add i64.const 1 i64.store
    local.get $frame i32.const 48 i32.add i64.const 4096 i64.store
    local.get $frame i32.const 56 i32.add i32.const 1 i32.store8
    local.get $frame i32.const 64 i32.add i64.const 100 i64.store
    local.get $frame i32.const 72 i32.add i32.const 1 i32.store
    local.get $frame i32.const 80 i32.add i32.const 1 i32.store8
    local.get $frame i32.const 88 i32.add i64.const 101 i64.store
    local.get $frame i32.const 96 i32.add i32.const 2 i32.store
    local.get $frame i32.const 104 i32.add i32.const 1 i32.store8
    local.get $frame i32.const 112 i32.add i64.const 102 i64.store
    local.get $frame i32.const 120 i32.add i32.const 3 i32.store
  )

  ;; [stat-at-error] error-code occupies the first payload slot and all record
  ;; presence bits are cleared. During cancellation the callback status is
  ;; copied only to satisfy task-return cleanup; the cancelled call does not
  ;; expose it as a business Result to the host.
  (func $write-error (param $frame i32) (param $code i32)
    local.get $frame i32.const 24 i32.add i32.const 1 i32.store8
    local.get $frame i32.const 32 i32.add local.get $code i32.store8
    local.get $frame i32.const 40 i32.add i64.const 0 i64.store
    local.get $frame i32.const 48 i32.add i64.const 0 i64.store
    local.get $frame i32.const 56 i32.add i32.const 0 i32.store8
    local.get $frame i32.const 64 i32.add i64.const 0 i64.store
    local.get $frame i32.const 72 i32.add i32.const 0 i32.store
    local.get $frame i32.const 80 i32.add i32.const 0 i32.store8
    local.get $frame i32.const 88 i32.add i64.const 0 i64.store
    local.get $frame i32.const 96 i32.add i32.const 0 i32.store
    local.get $frame i32.const 104 i32.add i32.const 0 i32.store8
    local.get $frame i32.const 112 i32.add i64.const 0 i64.store
    local.get $frame i32.const 120 i32.add i32.const 0 i32.store
  )

  ;; [stat-at-pending]
  (func $wait-on-stat-at (param $frame i32) (result i32)
    local.get $frame i32.const 20 i32.add i32.load
    i32.const 4 i32.shr_u
    local.get $frame i32.load
    call $waitable-join
    local.get $frame i32.load
    i32.const 4 i32.shl
    i32.const 2 i32.or
  )

  (func $finish (param $frame i32) (result i32)
    (local $tag i32) (local $dtype i32) (local $link i64) (local $size i64)
    (local $ap i32) (local $as i64) (local $an i32)
    (local $mp i32) (local $ms i64) (local $mn i32)
    (local $cp i32) (local $cs i64) (local $cn i32)
    local.get $frame i32.const 132 i32.add i32.load
    i32.eqz
    if
    else
      local.get $frame i32.const 132 i32.add i32.load
      call $subtask-drop
    end
    local.get $frame i32.const 24 i32.add i32.load8_u local.set $tag
    local.get $frame i32.const 32 i32.add i32.load8_u local.set $dtype
    local.get $frame i32.const 40 i32.add i64.load local.set $link
    local.get $frame i32.const 48 i32.add i64.load local.set $size
    local.get $frame i32.const 56 i32.add i32.load8_u local.set $ap
    local.get $frame i32.const 64 i32.add i64.load local.set $as
    local.get $frame i32.const 72 i32.add i32.load local.set $an
    local.get $frame i32.const 80 i32.add i32.load8_u local.set $mp
    local.get $frame i32.const 88 i32.add i64.load local.set $ms
    local.get $frame i32.const 96 i32.add i32.load local.set $mn
    local.get $frame i32.const 104 i32.add i32.load8_u local.set $cp
    local.get $frame i32.const 112 i32.add i64.load local.set $cs
    local.get $frame i32.const 120 i32.add i32.load local.set $cn
    local.get $frame i32.const 4 i32.add i32.load call $descriptor-drop
    local.get $frame i32.load call $waitable-set-drop
    i32.const 0 call $context-set-0
    local.get $tag
    local.get $dtype
    local.get $link
    local.get $size
    local.get $ap
    local.get $as
    local.get $an
    local.get $mp
    local.get $ms
    local.get $mn
    local.get $cp
    local.get $cs
    local.get $cn
    call $task-return-run
    local.get $frame
    call $frame-free
    i32.const 0
  )

  (func $start-stat-at (param $frame i32) (result i32)
    (local $status i32)
    local.get $frame i32.const 4 i32.add i32.load
    local.get $frame i32.const 8 i32.add i32.load
    local.get $frame i32.const 12 i32.add i32.load
    local.get $frame i32.const 16 i32.add i32.load
    local.get $frame i32.const 24 i32.add
    call $stat-at
    local.set $status
    local.get $frame i32.const 20 i32.add
    local.get $status
    i32.store
    local.get $status i32.const 2 i32.eq
    if (result i32)
      local.get $frame call $write-ready
      local.get $frame call $finish
    else
      local.get $frame call $wait-on-stat-at
    end
  )

  (func $run (type $async-run)
    (local $frame i32)
    call $frame-alloc
    local.tee $frame
    global.set $run-frame
    local.get $frame call $context-set-0
    local.get $frame call $waitable-set-new i32.store
    local.get $frame i32.const 4 i32.add local.get 0 i32.store
    local.get $frame i32.const 8 i32.add local.get 1 i32.store
    local.get $frame i32.const 12 i32.add local.get 2 i32.store
    local.get $frame i32.const 16 i32.add local.get 3 i32.store
    local.get $frame i32.const 20 i32.add i32.const 0 i32.store
    local.get $frame i32.const 24 i32.add i32.const 0 i32.store8
    local.get $frame i32.const 132 i32.add i32.const 0 i32.store
    local.get $frame call $start-stat-at
  )

  (func $cancel (type $async-cancel) (result i32)
    (local $handle i32) (local $status i32)
    ;; [subtask-cancel] cancellation releases only live async state; the
    ;; external stat side effect is never rolled back.
    global.get $run-frame
    i32.const 20
    i32.add
    i32.load
    i32.const 4 i32.shr_u
    local.tee $handle
    call $subtask-cancel
    local.set $status
    local.get $status
    i32.const 4
    i32.eq
    if
      local.get $handle
      call $subtask-drop
    end
    call $task-return-cancel
    i32.const 0
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
        local.get $frame call $write-ready
        local.get $frame call $finish
      else
        local.get $frame local.get 2 call $write-error
        local.get $frame call $finish
      end
    else
      local.get $frame call $wait-on-stat-at
    end
  )

  (func $cancel-callback (type $async-callback)
    unreachable
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

  (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" (func $run))
  (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" (func $callback))
  (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel" (func $cancel))
  (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel" (func $cancel-callback))
  (export "memory" (memory $memory))
  (export "cabi_realloc" (func $cabi-realloc))
  (export "_initialize" (func $_initialize))
)
