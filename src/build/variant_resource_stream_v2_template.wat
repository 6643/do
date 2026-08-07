(module
  ;; generic ABI v2 independent descriptor emitter template
  (type $source-acquire (func (param i32)))
  (type $stream-read (func (param i32) (param i32) (param i32) (result i32)))
  (type $future-read (func (param i32) (param i32) (result i32)))
  (type $drop (func (param i32)))
  (type $waitable-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $waitable-drop (func (param i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $async-run (func (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $task-return (func (param i32 i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (type $initialize (func))

  (import "__SOURCE_MODULE__" "__ACQUIRE__" (func $source-acquire (type $source-acquire)))
  (import "__SOURCE_MODULE__" "__STREAM_READ__" (func $stream-read (type $stream-read)))
  (import "__SOURCE_MODULE__" "__STREAM_DROP__" (func $stream-drop (type $drop)))
  (import "__SOURCE_MODULE__" "__FUTURE_READ__" (func $future-read (type $future-read)))
  (import "__SOURCE_MODULE__" "__FUTURE_DROP__" (func $future-drop (type $drop)))
  (import "__SOURCE_MODULE__" "__RESOURCE_DROP__" (func $ticket-drop (type $drop)))
  (import "$root" "[waitable-set-new]" (func $waitable-new (type $waitable-new)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[waitable-set-drop]" (func $waitable-drop (type $waitable-drop)))
  (import "$root" "[context-get-0]" (func $context-get (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set (type $context-set)))
  (import "[export]__PROBE_MODULE__" "__TASK_RETURN__" (func $task-return (type $task-return)))

  (memory (export "memory") 1)

  ;; Frame: 0 waitable-set, 4 stream, 8 future, 12 phase, 16 ticket,
  ;; 20 ticket-state, 64 event result, 80 completion Result.
  (global $frame-next (mut i32) (i32.const 1024))

  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 128
    i32.add
    global.set $frame-next
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    i32.const 128
    i32.add
    global.get $frame-next
    i32.eq
    if
    else
      unreachable
    end
    local.get $frame
    global.set $frame-next
  )

  (func $event-layout-markers
    ;; [event-result-pointer]
    i32.const __EVENT_RESULT_POINTER__
    drop
    ;; [event-tag-offset]
    i32.const __EVENT_TAG_OFFSET__
    drop
    ;; [event-payload-offset]
    i32.const __EVENT_PAYLOAD_OFFSET__
    drop
    ;; [event-size]
    i32.const __EVENT_SIZE__
    drop
    ;; [event-alignment]
    i32.const __EVENT_ALIGNMENT__
    drop
  )

  (func $wait-on-stream (param $frame i32) (result i32)
    local.get $frame
    i32.const 4
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
    i32.or
  )

  (func $wait-on-completion (param $frame i32) (result i32)
    local.get $frame
    i32.const 8
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
    i32.or
  )

  (func $release-ticket (param $frame i32) (local $handle i32)
    local.get $frame
    i32.const 20
    i32.add
    i32.load
    i32.const 2
    i32.eq
    if
      unreachable
    end
    local.get $frame
    i32.const 20
    i32.add
    i32.load
    i32.eqz
    if
      return
    end
    local.get $frame
    i32.const 16
    i32.add
    i32.load
    local.tee $handle
    i32.eqz
    if
      unreachable
    end
    local.get $frame
    i32.const 16
    i32.add
    i32.const 0
    i32.store
    local.get $handle
    call $ticket-drop
    local.get $frame
    i32.const 20
    i32.add
    i32.const 2
    i32.store
  )

  (func $cleanup (param $frame i32) (result i32) (local $handle i32)
    local.get $frame
    i32.const 8
    i32.add
    i32.load
    local.tee $handle
    i32.eqz
    if
    else
      local.get $handle
      call $future-drop
      local.get $frame
      i32.const 8
      i32.add
      i32.const 0
      i32.store
    end
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    local.tee $handle
    i32.eqz
    if
    else
      local.get $handle
      call $stream-drop
      local.get $frame
      i32.const 4
      i32.add
      i32.const 0
      i32.store
    end
    local.get $frame
    call $release-ticket
    local.get $frame
    i32.load
    call $waitable-drop
    local.get $frame
    i32.const 12
    i32.add
    i32.const 2
    i32.store
    i32.const 0
    call $context-set
    local.get $frame
    i32.const 80
    i32.add
    i32.load
    local.get $frame
    i32.const 84
    i32.add
    i32.load
    call $task-return
    local.get $frame
    call $frame-free
    i32.const 0
  )

  ;; Returns 1 only for failed(io), after storing the probe Result Err tag.
  (func $consume-event (param $frame i32) (result i32) (local $tag i32) (local $payload i32)
    local.get $frame
    i32.const 64
    i32.add
    i32.load
    local.set $tag
    local.get $tag
    i32.const 0
    i32.eq
    if (result i32)
      local.get $frame
      i32.const 68
      i32.add
      i32.load
      local.tee $payload
      i32.eqz
      if
        unreachable
      end
      local.get $frame
      i32.const 16
      i32.add
      local.get $payload
      i32.store
      local.get $frame
      i32.const 68
      i32.add
      i32.const 0
      i32.store
      local.get $frame
      i32.const 20
      i32.add
      i32.const 1
      i32.store
      i32.const 0
    else
      local.get $tag
      i32.const 1
      i32.eq
      if (result i32)
        i32.const 0
      else
        local.get $tag
        i32.const 2
        i32.eq
        if (result i32)
          local.get $frame
          i32.const 68
          i32.add
          i32.load
          i32.eqz
          if
          else
            unreachable
          end
          local.get $frame
          i32.const 80
          i32.add
          i32.const 1
          i32.store
          local.get $frame
          i32.const 84
          i32.add
          i32.const 0
          i32.store
          i32.const 1
        else
          unreachable
          i32.const 0
        end
      end
    end
  )

  (func $accept-completion (param $frame i32) (param $code i32) (result i32)
    local.get $frame
    call $cleanup
  )

  (func $start-completion (param $frame i32) (result i32) (local $code i32)
    local.get $frame
    i32.const 12
    i32.add
    i32.const 1
    i32.store
    local.get $frame
    i32.const 8
    i32.add
    i32.load
    local.get $frame
    i32.const 80
    i32.add
    call $future-read
    local.tee $code
    i32.const -1
    i32.eq
    if (result i32)
      local.get $frame
      call $wait-on-completion
    else
      local.get $frame
      local.get $code
      call $accept-completion
    end
  )

  (func $finish-event (param $frame i32) (param $failed i32) (result i32)
    local.get $failed
    if (result i32)
      local.get $frame
      call $cleanup
    else
      local.get $frame
      call $start-completion
    end
  )

  (func $accept-stream (param $frame i32) (param $code i32) (result i32) (local $failed i32)
    local.get $code
    i32.const 16
    i32.eq
    if (result i32)
      ;; [mode-before-event-consume]
      local.get $frame
      call $consume-event
      local.set $failed
      ;; [mode-after-event-consume]
      local.get $frame
      local.get $failed
      call $finish-event
    else
      local.get $code
      i32.const 17
      i32.eq
      if (result i32)
        local.get $frame
        call $start-completion
      else
        local.get $code
        i32.const 1
        i32.eq
        if (result i32)
          local.get $frame
          call $start-completion
        else
          unreachable
          i32.const 0
        end
      end
    end
  )

  (func $start-stream (param $frame i32) (result i32) (local $code i32)
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    local.get $frame
    i32.const 64
    i32.add
    i32.const 1
    call $stream-read
    local.tee $code
    i32.const -1
    i32.eq
    if (result i32)
      local.get $frame
      call $wait-on-stream
    else
      local.get $frame
      local.get $code
      call $accept-stream
    end
  )

  (func $accept-acquisition (param $frame i32) (param $payload i32) (result i32)
    local.get $frame
    i32.const 4
    i32.add
    local.get $payload
    i32.load
    i32.store
    local.get $frame
    i32.const 8
    i32.add
    local.get $payload
    i32.const 4
    i32.add
    i32.load
    i32.store
    local.get $frame
    call $start-stream
  )

  (func (export "[async-lift]__PROBE_MODULE__#run") (type $async-run) (result i32) (local $frame i32)
    call $frame-alloc
    local.tee $frame
    call $context-set
    local.get $frame
    call $waitable-new
    i32.store
    local.get $frame
    i32.const 16
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 20
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 80
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 84
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 4
    i32.add
    call $source-acquire
    local.get $frame
    i32.const 12
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    call $start-stream
  )

  (func (export "[callback][async-lift]__PROBE_MODULE__#run") (type $async-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    call $context-get
    local.set $frame
    local.get $event
    i32.const 1
    i32.eq
    if (result i32)
      local.get $frame
      local.get $payload
      call $accept-acquisition
    else
      local.get $event
      i32.const 2
      i32.eq
      if (result i32)
        local.get $frame
        local.get $payload
        call $accept-stream
      else
        local.get $event
        i32.const 4
        i32.eq
        if (result i32)
          local.get $frame
          local.get $payload
          call $accept-completion
        else
          unreachable
        end
      end
    end
  )

  (func (export "cabi_realloc") (type $cabi-realloc) (param i32 i32 i32 i32) (result i32)
    unreachable
    i32.const 0
  )

  (func (export "_initialize") (type $initialize))
)
