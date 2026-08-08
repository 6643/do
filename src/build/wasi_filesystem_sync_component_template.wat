(module
  (type $method (func (param i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $noargs (func))
  (type $root-new (func (result i32)))
  (type $root-join (func (param i32 i32)))
  (type $root-poll (func (param i32 i32) (result i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $async-run (func (param i32) (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[async-lower][method]descriptor.sync"
    (func $sync (type $method)))
  (import "wasi:filesystem/types@0.3.0-rc-2025-09-16" "[resource-drop]descriptor"
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
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]run"
    (func $task-return-run (type $root-join)))
  (memory $memory 1)
  (global $frame-next (mut i32) (i32.const 1024))
  (global $heap-next (mut i32) (i32.const 65536))
  ;; Unit Ok has no payload; error-code is the only payload arm.
  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 32
    i32.add
    global.set $frame-next)
  (func $frame-free (param $frame i32) local.get $frame drop)
  (func $wait-on-sync (param $frame i32) (result i32)
    local.get $frame i32.const 16 i32.add i32.load i32.const 4 i32.shr_u
    local.get $frame i32.load call $waitable-join
    local.get $frame i32.load i32.const 4 i32.shl i32.const 2 i32.or)
  (func $finish (param $frame i32) (result i32)
    (local $tag i32) (local $payload i32)
    local.get $frame i32.const 16 i32.add i32.load i32.const 2 i32.ne
    if
      local.get $frame i32.const 16 i32.add i32.load i32.const 4 i32.shr_u call $subtask-drop
    end
    local.get $frame i32.const 8 i32.add i32.load8_u local.set $tag
    local.get $frame i32.const 9 i32.add i32.load8_u local.set $payload
    local.get $frame i32.const 4 i32.add i32.load call $descriptor-drop
    local.get $frame i32.load call $waitable-set-drop
    i32.const 0 call $context-set-0
    local.get $tag local.get $payload call $task-return-run
    local.get $frame call $frame-free
    i32.const 0)
  (func $start-sync (param $frame i32) (result i32)
    (local $code i32)
    local.get $frame i32.const 4 i32.add i32.load
    local.get $frame i32.const 8 i32.add call $sync local.set $code
    local.get $frame i32.const 16 i32.add local.get $code i32.store
    local.get $code i32.const 2 i32.eq
    if (result i32) local.get $frame call $finish
    else local.get $frame call $wait-on-sync end)
  (func $run (type $async-run) (local $frame i32)
    call $frame-alloc local.tee $frame call $context-set-0
    local.get $frame call $waitable-set-new i32.store
    local.get $frame i32.const 4 i32.add local.get 0 i32.store
    local.get $frame i32.const 8 i32.add i32.const 0 i32.store
    local.get $frame i32.const 12 i32.add i32.const 0 i32.store
    local.get $frame i32.const 16 i32.add i32.const 0 i32.store
    local.get $frame call $start-sync)
  (func $callback (type $async-callback) (local $frame i32)
    call $context-get-0 local.set $frame
    local.get 0 i32.const 1 i32.eq
    if (result i32)
      local.get 2 i32.const 2 i32.eq
      if (result i32) local.get $frame call $finish
      else
        local.get $frame i32.const 8 i32.add i32.const 1 i32.store8
        local.get $frame i32.const 9 i32.add local.get 2 i32.store8
        local.get $frame call $finish
      end
    else local.get $frame call $wait-on-sync end)
  (func $cabi-realloc (type $cabi-realloc) (local $ptr i32)
    global.get $heap-next local.set $ptr
    local.get $ptr local.get 3 i32.add global.set $heap-next
    local.get $ptr)
  (func $_initialize (type $noargs))
  (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" (func $run))
  (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run" (func $callback))
  (export "memory" (memory $memory))
  (export "cabi_realloc" (func $cabi-realloc))
  (export "_initialize" (func $_initialize)))
