(module
  ;; Cancellation probe for the indirect descriptor.open-at async ABI.
  (type $method (func (param i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $noargs (func))
  (type $root-new (func (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-poll (func (param i32 i32) (result i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $async-run (func (param i32 i32 i32 i32 i32 i32) (result i32)))
  (type $async-cancel (func (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  ;; [open-at-task-return-layout] result tag, descriptor handle/error code.
  (type $task-return-open-at (func (param i32 i32)))

  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16"
    "[async-lower][method]descriptor.open-at" (func $open-at (type $method)))
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
  (import "$root" "[async-lower][subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $root-new)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $resource-drop)))
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16"
    "[task-return]run" (func $task-return-run (type $task-return-open-at)))
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16"
    "[task-return]cancel" (func $task-return-cancel (type $noargs)))

  (memory $memory 1)
  (global $run-frame (mut i32) (i32.const 0))
  (global $heap-next (mut i32) (i32.const 65536))

  ;; Fixed single-run frame: waitable @0, parent @4, path @8, path-len @12,
  ;; status @16, subtask @20, result tag/payload @32/36, params @48..71.
  ;; [open-at-call] [open-at-result-area] [open-at-path-copy]
  ;; [open-at-ready] [open-at-pending] [open-at-error]
  (func $wait-on-open-at (param $frame i32) (result i32)
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
    i32.or)

  (func $write-error (param $frame i32) (param $code i32)
    local.get $frame i32.const 32 i32.add i32.const 1 i32.store
    local.get $frame i32.const 36 i32.add local.get $code i32.store)

  (func $finish (param $frame i32) (result i32)
    (local $tag i32) (local $payload i32) (local $subtask i32)
    local.get $frame i32.const 32 i32.add i32.load local.set $tag
    local.get $frame i32.const 36 i32.add i32.load local.set $payload
    local.get $frame i32.const 20 i32.add i32.load local.set $subtask
    local.get $subtask i32.eqz
    if else local.get $subtask call $subtask-drop end
    local.get $frame i32.const 4 i32.add i32.load call $descriptor-drop
    local.get $frame i32.load call $waitable-set-drop
    i32.const 0 call $context-set-0
    local.get $tag local.get $payload call $task-return-run
    i32.const 0)

  (func $start-open-at (param $frame i32) (result i32)
    (local $status i32)
    local.get $frame i32.const 48 i32.add
    local.get $frame i32.const 4 i32.add i32.load i32.store
    local.get $frame i32.const 52 i32.add
    local.get $frame i32.const 72 i32.add i32.load i32.store
    local.get $frame i32.const 56 i32.add
    local.get $frame i32.const 8 i32.add i32.load i32.store
    local.get $frame i32.const 60 i32.add
    local.get $frame i32.const 12 i32.add i32.load i32.store
    local.get $frame i32.const 64 i32.add
    local.get $frame i32.const 76 i32.add i32.load i32.store
    local.get $frame i32.const 68 i32.add
    local.get $frame i32.const 80 i32.add i32.load i32.store
    local.get $frame i32.const 48 i32.add local.get $frame i32.const 32 i32.add
    call $open-at local.set $status
    local.get $frame i32.const 16 i32.add local.get $status i32.store
    local.get $status i32.const 2 i32.eq
    if (result i32) local.get $frame call $finish
    else local.get $frame call $wait-on-open-at end)

  (func $run (type $async-run)
    (local $frame i32)
    i32.const 1024 local.set $frame
    local.get $frame global.set $run-frame
    local.get $frame call $context-set-0
    local.get $frame call $waitable-set-new i32.store
    local.get $frame i32.const 4 i32.add local.get 0 i32.store
    local.get $frame i32.const 8 i32.add local.get 2 i32.store
    local.get $frame i32.const 12 i32.add local.get 3 i32.store
    local.get $frame i32.const 72 i32.add local.get 1 i32.store
    local.get $frame i32.const 76 i32.add local.get 4 i32.store
    local.get $frame i32.const 80 i32.add local.get 5 i32.store
    local.get $frame i32.const 20 i32.add i32.const 0 i32.store
    local.get $frame i32.const 32 i32.add i32.const 1 i32.store
    local.get $frame i32.const 36 i32.add i32.const 0 i32.store
    local.get $frame call $start-open-at)

  (func $cancel (type $async-cancel) (result i32)
    (local $frame i32) (local $handle i32) (local $status i32)
    global.get $run-frame local.set $frame
    local.get $frame i32.const 20 i32.add i32.load i32.const 4 i32.shr_u
    local.tee $handle call $subtask-cancel local.set $status
    local.get $status i32.const 4 i32.eq
    if local.get $handle call $subtask-drop end
    local.get $frame i32.const 4 i32.add i32.load call $descriptor-drop
    local.get $frame i32.load call $waitable-set-drop
    i32.const 0 call $context-set-0
    call $task-return-cancel
    i32.const 0)

  (func $callback (type $async-callback)
    (local $frame i32)
    call $context-get-0 local.set $frame
    local.get 0 i32.const 1 i32.eq
    if (result i32)
      local.get $frame i32.const 20 i32.add local.get 1 i32.store
      local.get 2 i32.const 2 i32.eq
      if (result i32) local.get $frame call $finish
      else local.get $frame local.get 2 call $write-error local.get $frame call $finish end
    else local.get $frame call $wait-on-open-at end)

  (func $cancel-callback (type $async-callback) unreachable)
  (func $cabi-realloc (type $cabi-realloc)
    (local $ptr i32)
    global.get $heap-next local.set $ptr
    local.get $ptr local.get 3 i32.add global.set $heap-next
    local.get $ptr)
  (func $_initialize (type $noargs))
  (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" (func $run))
  (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" (func $callback))
  (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel" (func $cancel))
  (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel" (func $cancel-callback))
  (export "memory" (memory $memory))
  (export "cabi_realloc" (func $cabi-realloc))
  (export "_initialize" (func $_initialize))
)
