(module
  (type $async-lower-send (func (param i32 i32) (result i32)))
  (type $resource-drop (func (param i32)))
  (type $task-return (func))
  (type $root-noargs (func))
  (type $root-cancel (func (param i32) (result i32)))
  (type $async-run (func (param i32) (result i32)))
  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "do:resource-probe-owned-error/http@0.1.0" "[async-lower]send"
    (func $send (type $async-lower-send)))
  (import "do:resource-probe-owned-error/http@0.1.0" "[resource-drop]request"
    (func $drop-request (type $resource-drop)))
  (import "do:resource-probe-owned-error/http@0.1.0" "[resource-drop]response"
    (func $drop-response (type $resource-drop)))
  (import "do:resource-probe-owned-error/http@0.1.0" "[resource-drop]error-resource"
    (func $drop-error-resource (type $resource-drop)))
  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $root-noargs)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $root-cancel)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $resource-drop)))
  (import "[export]$root" "[task-return]cancel" (func $task-return (type $task-return)))

  (memory (export "memory") 1)

  (func (export "[async-lift]cancel") (type $async-run)
    (local $subtask i32)
    local.get 0
    i32.const 0
    call $send
    local.set $subtask
    local.get $subtask
    i32.const 2
    i32.eq
    if (result i32)
      call $task-return
      i32.const 0
    else
      local.get $subtask
      i32.const 4
      i32.shr_u
      call $subtask-cancel
      i32.const 4
      i32.ne
      if
        unreachable
      end
      local.get $subtask
      i32.const 4
      i32.shr_u
      call $subtask-drop
      call $task-return
      i32.const 0
    end
  )

  (func (export "[callback][async-lift]cancel") (type $async-run-callback)
    unreachable)
  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
  (func (export "_initialize"))
)
