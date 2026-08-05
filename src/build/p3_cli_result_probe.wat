(module
  (type $async-lower-run (func (param i32) (result i32)))
  (type $task-return (func (param i32)))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $async-run (func (result i32)))
  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (import "wasi:cli/run@0.3.0" "[async-lower]run" (func $host-run (type $async-lower-run)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (param i32 i32) (result i32)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))
  (memory (export "memory") 1)
  (global $frame-free (mut i32) (i32.const 0))
  (global $frame-next (mut i32) (i32.const [frame-size]))
  (func $frame-alloc (result i32) (local $frame i32)
    global.get $frame-free local.tee $frame i32.eqz
    if (result i32)
      global.get $frame-next local.set $frame
      global.get $frame-next i32.const [frame-size] i32.add global.set $frame-next
      global.get $frame-next memory.size i32.const 16 i32.shl i32.gt_u
      if i32.const 1 memory.grow i32.const -1 i32.eq if unreachable end end
      local.get $frame
    else
      local.get $frame i32.load global.set $frame-free local.get $frame
    end)
  (func $frame-free (param $frame i32)
    local.get $frame global.get $frame-free i32.store
    local.get $frame global.set $frame-free)
  (func (export "[async-lift]run") (type $async-run) (local $frame i32) (local $subtask i32)
    call $frame-alloc local.tee $frame
    i32.const [waitable-set-offset] i32.add call $waitable-set-new i32.store
    local.get $frame call $context-set-0
    local.get $frame i32.const [completion-value-offset] i32.add call $host-run local.set $subtask
    local.get $subtask i32.const 2 i32.eq
    if (result i32)
      local.get $frame i32.const [completion-value-offset] i32.add i32.load [completion-transform]call $task-return
      i32.const 0 call $context-set-0
      local.get $frame call $frame-free
      i32.const 0
    else
      local.get $subtask i32.const 4 i32.shr_u
      local.get $frame i32.const [waitable-set-offset] i32.add i32.load call $waitable-join
      local.get $frame i32.const [waitable-set-offset] i32.add i32.load i32.const 4 i32.shl i32.const 2 i32.or
    end)
  (func (export "[callback][async-lift]run") (type $async-run-callback) (local $frame i32)
    call $context-get-0 local.set $frame
    local.get 0 i32.const 1 i32.eq local.get 2 i32.const 2 i32.eq i32.and
    if (result i32)
      local.get $frame i32.const [completion-value-offset] i32.add i32.load [completion-transform]call $task-return
      i32.const 0 call $context-set-0
      local.get $frame call $frame-free
      i32.const 0
    else
      local.get $frame i32.const [waitable-set-offset] i32.add i32.load i32.const 4 i32.shl i32.const 2 i32.or
    end)

  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
)
