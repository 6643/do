(module
  ;; [filesystem-write-via-stream]
  ;; Frame: waitable=0, descriptor=4, readable=8, writable=12,
  ;; method-task=16, write-task=20, phase=24, method-result=28,
  ;; write-result=32, writer-closed=36, offset=40, result-tag=48,
  ;; result-payload=52, method-subtask=56, cancel-mask=44, frame-size=72.
  (type $method (func (param i32 i32 i64 i32) (result i32)))
  (type $stream-new (func (result i64)))
  (type $stream-cancel (func (param i32) (result i32)))
  (type $stream-drop (func (param i32)))
  (type $stream-io (func (param i32 i32 i32) (result i32)))
  (type $waitable-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $waitable-drop (func (param i32)))
  (type $waitable-poll (func (param i32 i32) (result i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $subtask-drop (func (param i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $task-cancel (func))
  (type $async-run (func (param i32 i64) (result i32)))
  (type $async-cancel (func (result i32)))
  (type $callback (func (param i32 i32 i32) (result i32)))
  (type $task-return (func))
  (type $realloc (func (param i32 i32 i32 i32) (result i32)))
  (type $initialize (func))

  (import "[method-module]" "[method-name]" (func $write-via-stream (type $method)))
  (import "[method-module]" "[stream-new-name]" (func $stream-new (type $stream-new)))
  (import "[method-module]" "[stream-cancel-read-name]" (func $stream-cancel-read (type $stream-cancel)))
  (import "[method-module]" "[async-lower][stream-cancel-write-name]" (func $stream-cancel-write (type $stream-cancel)))
  (import "[method-module]" "[stream-drop-readable-name]" (func $stream-drop-readable (type $stream-drop)))
  (import "[method-module]" "[stream-drop-writable-name]" (func $stream-drop-writable (type $stream-drop)))
  (import "[method-module]" "[stream-read-name]" (func $stream-read (type $stream-io)))
  (import "[method-module]" "[stream-write-name]" (func $stream-write (type $stream-io)))
  (import "[method-module]" "[resource-drop-name]" (func $descriptor-drop (type $stream-drop)))

  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-poll)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-poll)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $subtask-drop)))
  (import "$root" "[async-lower][subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-cancel)))
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]run" (func $task-return-run (type $task-return)))
  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]cancel" (func $task-return-cancel (type $task-return)))

  (memory (export "memory") 2)
  (global $frame-next (mut i32) (i32.const 1024))
  (global $heap-next (mut i32) (i32.const 65536))
  (global $run-frame (mut i32) (i32.const 0))

  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 72
    i32.add
    global.set $frame-next)

  (func $wait-on-stream (param $frame i32) (result i32)
    local.get $frame
    i32.const 12
    i32.add
    i32.load
    local.get $frame
    i32.load
    call $waitable-join
    local.get $frame
    i32.load
    i32.const 4
    i32.shl
    i32.const 2
    i32.or)

  (func $wait-on-subtask (param $frame i32) (param $task i32) (result i32)
    local.get $task
    local.get $frame
    i32.load
    call $waitable-join
    local.get $frame
    i32.load
    i32.const 4
    i32.shl
    i32.const 2
    i32.or)

  (func $close-writer (param $frame i32)
    local.get $frame
    i32.const 36
    i32.add
    i32.load
    i32.eqz
    if
      local.get $frame
      i32.const 12
      i32.add
      i32.load
      call $stream-drop-writable
      local.get $frame
      i32.const 12
      i32.add
      i32.const 0
      i32.store
      local.get $frame
      i32.const 36
      i32.add
      i32.const 1
      i32.store
    end)

  (func $cleanup (param $frame i32) (param $cancelled i32) (result i32)
    local.get $frame i32.const 36 i32.add i32.load i32.eqz
    if
      local.get $frame call $close-writer
    end
    local.get $cancelled
    i32.const 2
    i32.ne
    if
      local.get $frame i32.const 56 i32.add i32.load
      i32.eqz
      if
      else
        local.get $frame i32.const 56 i32.add i32.load
        i32.const 2
        i32.ne
        if
        local.get $frame i32.const 56 i32.add i32.load
        call $subtask-drop
        end
      end
    end
    local.get $frame i32.const 56 i32.add
    i32.const 0
    i32.store
    local.get $frame i32.const 4 i32.add i32.load
    call $descriptor-drop
    local.get $frame i32.load
    call $waitable-set-drop
    i32.const 0
    call $context-set-0
    i32.const 0
    global.set $run-frame
    local.get $cancelled
    if
      call $task-return-cancel
    else
      call $task-return-run
    end
    i32.const 0)

  (func $run (export "[run-lift]" ) (type $async-run)
    (local $frame i32) (local $pair i64) (local $method-task i32) (local $write-task i32)
    call $frame-alloc
    local.set $frame
    local.get $frame
    global.set $run-frame
    local.get $frame
    call $context-set-0
    local.get $frame
    call $waitable-set-new
    i32.store
    local.get $frame i32.const 4 i32.add local.get 0 i32.store
    local.get $frame i32.const 40 i32.add local.get 1 i64.store
    local.get $frame i32.const 44 i32.add i32.const 0 i32.store
    local.get $frame i32.const 16 i32.add i32.const 0 i32.store
    local.get $frame i32.const 20 i32.add i32.const 0 i32.store
    local.get $frame i32.const 24 i32.add i32.const 0 i32.store
    local.get $frame i32.const 28 i32.add i32.const 0 i32.store
    local.get $frame i32.const 32 i32.add i32.const 0 i32.store
    local.get $frame i32.const 36 i32.add i32.const 0 i32.store
    local.get $frame i32.const 52 i32.add i32.const 0 i32.store
    local.get $frame i32.const 56 i32.add i32.const 0 i32.store
    local.get $frame i32.const 8 i32.add
    call $stream-new
    local.tee $pair
    i32.wrap_i64
    i32.store
    local.get $frame i32.const 12 i32.add
    local.get $pair
    i64.const 32
    i64.shr_u
    i32.wrap_i64
    i32.store
    local.get 0
    ;; A WIT stream parameter is the readable end. The writable end remains
    ;; owned by the producer until the deferred close path runs.
    local.get $frame i32.const 8 i32.add i32.load
    local.get 1
    local.get $frame i32.const 28 i32.add
    call $write-via-stream
    local.set $method-task
    local.get $frame i32.const 16 i32.add
    local.get $method-task
    i32.store
    local.get $frame i32.const 56 i32.add
    local.get $method-task
    i32.const 2
    i32.eq
    if (result i32)
      i32.const 2
    else
      local.get $method-task
      i32.const 4
      i32.shr_u
    end
    i32.store
    ;; The method owns the readable end after the async call lowers its
    ;; stream parameter.
    local.get $frame i32.const 8 i32.add
    i32.const 0
    i32.store
    ;; The bounded source fixture writes the literal byte `65` at offset 512.
    i32.const 512
    i32.const 65
    i32.store8
    local.get $frame i32.const 12 i32.add i32.load
    i32.const 512
    i32.const 1
    call $stream-write
    local.set $write-task
    local.get $frame i32.const 20 i32.add
    local.get $write-task
    i32.store
    local.get $frame i32.const 24 i32.add
    i32.const 1
    i32.store
    local.get $write-task
    i32.const -1
    i32.eq
    if (result i32)
      local.get $frame
      call $wait-on-stream
    else
      local.get $frame
      call $close-writer
      local.get $method-task
      i32.const 2
      i32.eq
      if (result i32)
        local.get $frame
        i32.const 0
        call $cleanup
      else
        local.get $frame i32.const 24 i32.add
        i32.const 2
        i32.store
        local.get $frame
        local.get $frame
        i32.const 56
        i32.add
        i32.load
        call $wait-on-subtask
      end
    end)

  (func $cancel (export "[cancel-lift]") (type $async-cancel)
    (local $frame i32) (local $phase i32) (local $status i32)
    global.get $run-frame
    local.set $frame
    local.get $frame
    i32.eqz
    if
      i32.const 0
      return
    end
    local.get $frame i32.const 24 i32.add i32.load local.set $phase
    local.get $frame i32.const 24 i32.add i32.const 5 i32.store
    local.get $phase
    i32.const 1
    i32.eq
    local.get $phase
    i32.const 3
    i32.eq
    i32.or
    if
      local.get $frame i32.const 12 i32.add i32.load
      i32.eqz
      if
      else
        local.get $frame i32.const 12 i32.add i32.load
        i32.const 0
        call $waitable-join
        local.get $frame i32.const 12 i32.add i32.load
        call $stream-cancel-write
        local.set $status
        local.get $status
        i32.const -1
        i32.ne
        if
          local.get $frame i32.const 44 i32.add
          local.get $frame i32.const 44 i32.add i32.load
          i32.const 1
          i32.or
          i32.store
        end
        local.get $frame i32.const 12 i32.add i32.load
        local.get $frame i32.load
        call $waitable-join
      end
      local.get $frame i32.const 56 i32.add i32.load
      i32.const 2
      i32.ne
      if
        ;; Detach a method subtask from the run waitable set while cancelling
        ;; it, then rejoin it so its terminal event wakes the run callback.
        local.get $frame i32.const 56 i32.add i32.load
        i32.const 0
        call $waitable-join
        local.get $frame i32.const 56 i32.add i32.load
        call $subtask-cancel
        local.set $status
        local.get $status
        i32.const -1
        i32.ne
        if
          local.get $frame i32.const 44 i32.add
          local.get $frame i32.const 44 i32.add i32.load
          i32.const 2
          i32.or
          i32.store
        end
        local.get $frame i32.const 56 i32.add i32.load
        local.get $frame i32.load
        call $waitable-join
      end
    else
      local.get $frame i32.const 56 i32.add i32.load
      i32.const 0
      call $waitable-join
      local.get $frame i32.const 56 i32.add i32.load
      call $subtask-cancel
      local.set $status
      local.get $status
      i32.const -1
      i32.ne
      if
        local.get $frame i32.const 44 i32.add
        local.get $frame i32.const 44 i32.add i32.load
        i32.const 2
        i32.or
        i32.store
      end
      local.get $frame i32.const 56 i32.add i32.load
      local.get $frame i32.load
      call $waitable-join
    end
    local.get $frame i32.const 12 i32.add i32.load
    i32.eqz
    if
      local.get $frame i32.const 44 i32.add
      local.get $frame i32.const 44 i32.add i32.load
      i32.const 1
      i32.or
      i32.store
    end
    local.get $frame i32.const 56 i32.add i32.load
    i32.const 2
    i32.eq
    if
      local.get $frame i32.const 44 i32.add
      local.get $frame i32.const 44 i32.add i32.load
      i32.const 2
      i32.or
      i32.store
    end
    call $task-return-cancel
    i32.const 0)

  (func $callback (export "[run-callback]") (type $callback) (local $frame i32) (local $phase i32)
    call $context-get-0
    local.set $frame
    local.get $frame i32.eqz
    if
      i32.const 0
      return
    end
    local.get $frame i32.const 24 i32.add i32.load local.set $phase
    local.get 0
    i32.const 6
    i32.eq
    if (result i32)
      ;; event=6 is the CANCELLED event delivered to the run task. The task
      ;; must acknowledge it with task.cancel; task-return.cancel belongs to
      ;; the separate control export.
      call $task-cancel
      i32.const 0
    else
      local.get 0
      i32.const 3
      i32.eq
      if (result i32)
        local.get $phase
        i32.const 1
        i32.eq
        if (result i32)
          local.get 2
          i32.const 15
          i32.and
          i32.const 2
          i32.eq
          if (result i32)
            local.get $frame
            i32.const 1
            call $cleanup
          else
            local.get $frame
            call $close-writer
            local.get $frame i32.const 52 i32.add i32.load
            i32.eqz
            if (result i32)
              local.get $frame i32.const 24 i32.add i32.const 2 i32.store
              local.get $frame
              local.get $frame i32.const 56 i32.add i32.load
              call $wait-on-subtask
            else
              local.get $frame
              i32.const 0
              call $cleanup
            end
          end
        else
          local.get $phase
          i32.const 5
          i32.eq
          if (result i32)
            local.get $frame i32.const 44 i32.add
            local.get $frame i32.const 44 i32.add i32.load
            i32.const 1
            i32.or
            i32.store
            local.get $frame i32.const 44 i32.add i32.load
            i32.const 3
            i32.eq
            if (result i32)
              local.get $frame
              i32.const 0
              call $cleanup
            else
              local.get $frame
              i32.load
              i32.const 4
              i32.shl
              i32.const 2
              i32.or
            end
          else
            local.get $phase
          i32.const 4
          i32.eq
          if (result i32)
            local.get $frame
            call $close-writer
            local.get $frame
            i32.const 0
            call $cleanup
          else
            local.get $frame
            i32.const 1
            call $cleanup
          end
          end
        end
      else
        local.get 0
        i32.const 1
        i32.eq
        if (result i32)
          local.get $phase
          i32.const 1
          i32.eq
          if (result i32)
            local.get $frame i32.const 52 i32.add i32.const 1 i32.store
            local.get $frame
            call $wait-on-stream
          else
            local.get $phase
            i32.const 2
            i32.eq
            if (result i32)
              local.get $frame
              i32.const 0
              call $cleanup
            else
              local.get $phase
              i32.const 5
              i32.eq
              if (result i32)
                local.get $frame i32.const 44 i32.add
                local.get $frame i32.const 44 i32.add i32.load
                i32.const 2
                i32.or
                i32.store
                local.get $frame i32.const 44 i32.add i32.load
                i32.const 3
                i32.eq
                if (result i32)
                  local.get $frame
                  i32.const 0
                  call $cleanup
                else
                  local.get $frame
                  i32.load
                  i32.const 4
                  i32.shl
                  i32.const 2
                  i32.or
                end
              else
                local.get $frame
                i32.const 1
                call $cleanup
              end
            end
          end
        else
          local.get $frame
          i32.const 1
          call $cleanup
        end
      end
    end)

  (func $cancel-callback (export "[cancel-callback]") (type $callback)
    unreachable)

  (func $cabi-realloc (export "cabi_realloc") (type $realloc)
    (local $ptr i32)
    global.get $heap-next
    local.set $ptr
    local.get $ptr
    local.get 3
    i32.add
    global.set $heap-next
    local.get $ptr)
  (func $_initialize (export "_initialize") (type $initialize))
)
