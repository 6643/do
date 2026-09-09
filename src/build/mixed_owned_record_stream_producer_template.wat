(module
  (type $resource-drop (func (param i32)))
  (type $make-ticket (func (param i32) (result i32)))
  (type $async-lower (func (param i32 i32) (result i32)))
  (type $stream-new (func (result i64)))
  (type $stream-cancel (func (param i32) (result i32)))
  (type $stream-drop (func (param i32)))
  (type $stream-io (func (param i32 i32 i32) (result i32)))
  (type $task-cancel (func))
  (type $backpressure (func))
  (type $waitable-set-new (func (result i32)))
  (type $waitable (func (param i32 i32)))
  (type $waitable-poll (func (param i32 i32) (result i32)))
  (type $waitable-drop (func (param i32)))
  (type $subtask-drop (func (param i32)))
  (type $subtask-cancel (func (param i32) (result i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $async-run-u32 (func (param i32) (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $task-return (func (param i32 i32)))
  (type $initialize (func))

  (import "do:g6-2-owned-record-mixed-producer/types@0.1.0" "[resource-drop]ticket"
    (func $ticket-drop (type $resource-drop)))
  (import "do:g6-2-owned-record-mixed-producer/source@0.1.0" "make-ticket"
    (func $make-ticket (type $make-ticket)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[async-lower]consume-via-stream"
    (func $sink-call (type $async-lower)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[stream-new-0]consume-via-stream"
    (func $stream-new (type $stream-new)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[stream-cancel-read-0]consume-via-stream"
    (func $stream-cancel-read (type $stream-cancel)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[stream-cancel-write-0]consume-via-stream"
    (func $stream-cancel-write (type $stream-cancel)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[stream-drop-readable-0]consume-via-stream"
    (func $stream-drop-readable (type $stream-drop)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[stream-drop-writable-0]consume-via-stream"
    (func $stream-drop-writable (type $stream-drop)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[async-lower][stream-read-0]consume-via-stream"
    (func $stream-read (type $stream-io)))
  (import "do:g6-2-owned-record-mixed-producer/sink@0.1.0" "[async-lower][stream-write-0]consume-via-stream"
    (func $stream-write (type $stream-io)))

  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-cancel)))
  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $backpressure)))
  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $backpressure)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-poll)))
  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-poll)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable)))
  (import "$root" "[thread-yield]" (func $thread-yield (type $waitable-set-new)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (type $subtask-drop)))
  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
  (import "$root" "[context-get-0]" (func $context-get (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set (type $context-set)))
  (import "[export]$root" "[task-return]produce" (func $task-return (type $task-return)))

  (memory (export "memory") 2)
  (global $frame-next (mut i32) (i32.const 1024))

  ;; Frame: 0 result tag, 4 result payload, 8 waitable set, 12 readable,
  ;; 16 writable, 20 record ownership state, 32 sink subtask,
  ;; 36 pending-write state, 40 mode, 64 mixed-entry slot (code + ticket).
  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 128
    i32.add
    global.set $frame-next
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    global.set $frame-next
  )

  (func $layout-markers
    ;; [producer-record-byte-size] 8
    i32.const 8
    drop
    ;; [producer-record-alignment] 4
    i32.const 4
    drop
    ;; [producer-record-code-offset] 0
    i32.const 0
    drop
    ;; [producer-record-ticket-offset] 4
    i32.const 4
    drop
    ;; [producer-stream-capacity] 1
    i32.const 1
    drop
    ;; [producer-ticket-seed] 111
    i32.const 111
    drop
    ;; [producer-record-transfer]
    ;; [producer-resource-drop-exactly-once]
    ;; [producer-child-before-parent-cleanup]
  )


  (func $wait-on-subtask (param $frame i32) (result i32)
    local.get $frame
    i32.const 32
    i32.add
    i32.load
    local.get $frame
    i32.const 8
    i32.add
    i32.load
    call $waitable-join
    local.get $frame
    i32.const 8
    i32.add
    i32.load
    i32.const 4
    i32.shl
    i32.const 2
    i32.or
  )

  ;; The guest owns the ticket while state=1. State=2 means the stream/host
  ;; owns the ticket after a successful record transfer; state=3 is released.
  (func $drop-guest-ticket (param $frame i32)
    (local $handle i32)
    local.get $frame
    i32.const 68
    i32.add
    i32.load
    local.tee $handle
    i32.eqz
    if
    else
      local.get $handle
      call $ticket-drop
      local.get $frame
      i32.const 68
      i32.add
      i32.const 0
      i32.store
    end
  )

  (func $release-guest-record (param $frame i32)
    local.get $frame
    i32.const 20
    i32.add
    i32.load
    i32.const 3
    i32.eq
    if
      unreachable
    end
    local.get $frame
    i32.const 20
    i32.add
    i32.load
    i32.const 1
    i32.eq
    if
      local.get $frame
      call $drop-guest-ticket
    end
    local.get $frame
    i32.const 20
    i32.add
    i32.const 3
    i32.store
  )

  (func $transfer-record (param $frame i32)
    local.get $frame
    i32.const 20
    i32.add
    i32.load
    i32.const 1
    i32.eq
    if
      local.get $frame
      i32.const 68
      i32.add
      i32.const 0
      i32.store
      local.get $frame
      i32.const 20
      i32.add
      i32.const 2
      i32.store
    end
  )

  (func $post-transfer-cancel (param $frame i32)
    local.get $frame
    i32.load offset=40
    i32.const 5
    i32.eq
    local.get $frame
    i32.load offset=40
    i32.const 7
    i32.eq
    i32.or
    if
      local.get $frame
      i32.load offset=32
      call $subtask-cancel
      drop
    end
  )

  (func $cleanup (param $frame i32) (param $tag i32) (param $payload i32) (result i32)
    local.get $frame
    i32.const 32
    i32.add
    i32.load
    i32.eqz
    if
    else
      local.get $frame
      i32.const 32
      i32.add
      i32.load
      call $subtask-drop
      local.get $frame
      i32.const 32
      i32.add
      i32.const 0
      i32.store
    end
    local.get $frame
    i32.const 16
    i32.add
    i32.load
    i32.eqz
    if
    else
      local.get $frame
      i32.const 16
      i32.add
      i32.load
      call $stream-drop-writable
      local.get $frame
      i32.const 16
      i32.add
      i32.const 0
      i32.store
    end
    local.get $frame
    i32.const 12
    i32.add
    i32.load
    i32.eqz
    if
    else
      local.get $frame
      i32.const 12
      i32.add
      i32.load
      call $stream-drop-readable
      local.get $frame
      i32.const 12
      i32.add
      i32.const 0
      i32.store
    end
    local.get $frame
    call $release-guest-record
    local.get $frame
    i32.const 8
    i32.add
    i32.load
    call $waitable-set-drop
    local.get $tag
    local.get $payload
    call $task-return
    local.get $frame
    call $frame-free
    i32.const 0
  )

  (func $mode-code (param $mode i32) (result i32)
    local.get $mode
    i32.const 1
    i32.eq
    if (result i32)
      i32.const 9
    else
      local.get $mode
      i32.const 2
      i32.eq
      if (result i32)
        i32.const 11
      else
        local.get $mode
        i32.const 3
        i32.eq
        if (result i32)
          i32.const 13
        else
          local.get $mode
          i32.const 4
          i32.eq
          if (result i32)
            i32.const 15
          else
            local.get $mode
            i32.const 5
            i32.eq
            if (result i32)
              i32.const 17
            else
              local.get $mode
              i32.const 6
              i32.eq
              if (result i32)
                i32.const 19
              else
                local.get $mode
                i32.const 7
                i32.eq
                if (result i32)
                  i32.const 21
                else
                  i32.const 7
                end
              end
            end
          end
        end
      end
    end
  )

  (func $mode-error-code (param $mode i32) (result i32)
    ;; sink-error-before maps to Io; all other non-invalid failures map to Pipe.
    local.get $mode
    i32.const 2
    i32.eq
    if (result i32)
      i32.const 0
    else
      i32.const 1
    end
  )

  (func $mode-seed (param $mode i32) (result i32)
    local.get $mode
    i32.const 1
    i32.eq
    if (result i32)
      i32.const 222
    else
      local.get $mode
      i32.const 2
      i32.eq
      if (result i32)
        i32.const 333
      else
        local.get $mode
        i32.const 3
        i32.eq
        if (result i32)
          i32.const 444
        else
          local.get $mode
          i32.const 4
          i32.eq
          if (result i32)
            i32.const 555
          else
            local.get $mode
            i32.const 5
            i32.eq
            if (result i32)
              i32.const 666
            else
              local.get $mode
              i32.const 6
              i32.eq
              if (result i32)
                i32.const 777
              else
                local.get $mode
                i32.const 7
                i32.eq
                if (result i32)
                  i32.const 888
                else
                  i32.const 111
                end
              end
            end
          end
        end
      end
    end
  )

  (func $make-record (param $frame i32) (param $mode i32) (result i32)
    (local $handle i32)
    ;; Invalid mode is rejected before stream and ticket creation.
    local.get $mode
    i32.const 255
    i32.eq
    if
      i32.const -1
      return
    end
    local.get $frame
    i32.const 64
    i32.add
    local.get $mode
    call $mode-code
    i32.store
    local.get $mode
    call $mode-seed
    call $make-ticket
    local.tee $handle
    i32.eqz
    if
      i32.const -1
      return
    end
    local.get $frame
    i32.const 68
    i32.add
    local.get $handle
    i32.store
    local.get $frame
    i32.const 20
    i32.add
    i32.const 1
    i32.store
    i32.const 0
  )

  (func $write-record (param $frame i32) (result i32) (local $status i32)
    ;; [producer-record-transfer]
    ;; [mode-before-transfer]
    ;; [mode-before-stream-write]
    local.get $frame
    i32.const 16
    i32.add
    i32.load
    local.get $frame
    i32.const 64
    i32.add
    i32.const 1
    call $stream-write
    local.tee $status
    i32.const 15
    i32.and
    i32.eqz
    if (result i32)
      local.get $frame
      call $transfer-record
      local.get $frame
      i32.load offset=40
      i32.const 5
      i32.eq
      local.get $frame
      i32.load offset=40
      i32.const 7
      i32.eq
      i32.or
      if (result i32)
        local.get $frame
        call $post-transfer-cancel
        local.get $frame
        i32.const 1
        local.get $frame
        i32.load offset=40
        call $mode-error-code
        call $cleanup
      else
        local.get $frame
        i32.const 16
        i32.add
        i32.load
        call $stream-drop-writable
        local.get $frame
        i32.const 16
        i32.add
        i32.const 0
        i32.store
        local.get $frame
        i32.const 32
        i32.add
        i32.load
        i32.eqz
        if (result i32)
          local.get $frame
          i32.const 0
          i32.const 0
          call $cleanup
        else
          local.get $frame
          call $wait-on-subtask
        end
      end
    else
      local.get $status
      i32.const -1
      i32.eq
      if (result i32)
        local.get $frame
        i32.const 36
        i32.add
        i32.const 1
        i32.store
        local.get $frame
        i32.const 16
        i32.add
        i32.load
        local.get $frame
        i32.const 8
        i32.add
        i32.load
        call $waitable-join
        local.get $frame
        i32.const 8
        i32.add
        i32.load
        i32.const 4
        i32.shl
        i32.const 2
        i32.or
      else
        local.get $status
        i32.const 4
        i32.shr_u
        i32.eqz
        if (result i32)
          local.get $frame
          i32.const 1
          local.get $frame
          i32.load offset=40
          call $mode-error-code
          call $cleanup
        else
          local.get $frame
          call $transfer-record
          local.get $frame
          i32.const 16
          i32.add
          i32.load
          call $stream-drop-writable
          local.get $frame
          i32.const 16
          i32.add
          i32.const 0
          i32.store
          local.get $frame
          i32.const 32
          i32.add
          i32.load
          i32.eqz
          if (result i32)
            local.get $frame
            i32.const 1
            local.get $frame
            i32.load offset=40
            call $mode-error-code
            call $cleanup
          else
            local.get $frame
            call $wait-on-subtask
          end
        end
      end
    end
  )

  (func (export "[async-lift]produce") (type $async-run-u32) (param $mode i32) (result i32)
    (local $frame i32)
    (local $pair i64)
    (local $status i32)
    (local $subtask i32)
    call $frame-alloc
    local.tee $frame
    call $context-set
    local.get $frame
    call $waitable-set-new
    i32.store offset=8
    local.get $frame
    i32.const 0
    i32.store offset=12
    local.get $frame
    i32.const 0
    i32.store offset=16
    local.get $frame
    i32.const 0
    i32.store offset=20
    local.get $frame
    i32.const 0
    i32.store offset=24
    local.get $frame
    i32.const 0
    i32.store offset=28
    local.get $frame
    i32.const 0
    i32.store offset=32
    local.get $frame
    i32.const 0
    i32.store offset=36
    local.get $frame
    local.get $mode
    i32.store offset=40
    local.get $frame
    local.get $mode
    call $make-record
    local.tee $status
    i32.eqz
    if
    else
      local.get $frame
      i32.const 1
      i32.const 2
      call $cleanup
      return
    end
    call $stream-new
    local.tee $pair
    drop
    local.get $frame
    i32.const 12
    i32.add
    local.get $pair
    i32.wrap_i64
    i32.store
    local.get $frame
    i32.const 16
    i32.add
    local.get $pair
    i64.const 32
    i64.shr_u
    i32.wrap_i64
    i32.store
    local.get $frame
    call $context-set
    local.get $frame
    i32.load offset=12
    local.get $frame
    call $sink-call
    local.set $subtask
    ;; The async-lowered sink consumes the readable end when its parameter is
    ;; lowered.  Ownership has moved to the host task, so cleanup must not
    ;; attempt a guest drop for this handle.
    local.get $frame
    i32.const 0
    i32.store offset=12
    local.get $subtask
    i32.const 2
    i32.eq
    if
      local.get $frame
      i32.const 0
      i32.store offset=32
    else
      local.get $frame
      local.get $subtask
      i32.const 4
      i32.shr_u
      i32.store offset=32
    end
    local.get $frame
    i32.load offset=40
    i32.const 4
    i32.eq
    if
      local.get $frame
      i32.load offset=32
      call $subtask-cancel
      drop
      local.get $frame
      i32.const 1
      i32.const 1
      call $cleanup
      return
    end
    local.get $frame
    i32.load offset=40
    i32.const 6
    i32.eq
    if
      local.get $frame
      i32.load offset=32
      call $subtask-cancel
      drop
      local.get $frame
      i32.const 1
      i32.const 1
      call $cleanup
      return
    end
    local.get $frame
    call $write-record
  )

  (func (export "[callback][async-lift]produce") (type $async-callback)
    (param $event i32) (param $index i32) (param $payload i32) (result i32)
    (local $frame i32)
    call $context-get
    local.set $frame
    local.get $event
    i32.const 3
    i32.eq
    if (result i32)
      local.get $payload
      i32.const 15
      i32.and
      i32.eqz
      if (result i32)
        local.get $frame
        call $transfer-record
        local.get $frame
        i32.load offset=40
        i32.const 5
        i32.eq
        local.get $frame
        i32.load offset=40
        i32.const 7
        i32.eq
        i32.or
        if (result i32)
          local.get $frame
          call $post-transfer-cancel
          local.get $frame
          i32.const 1
          local.get $frame
          i32.load offset=40
          call $mode-error-code
          call $cleanup
        else
          local.get $frame
          i32.const 16
          i32.add
          i32.load
          call $stream-drop-writable
          local.get $frame
          i32.const 16
          i32.add
          i32.const 0
          i32.store
          local.get $frame
          i32.const 32
          i32.add
          i32.load
          i32.eqz
          if (result i32)
            local.get $frame
            i32.const 0
            i32.const 0
            call $cleanup
          else
            local.get $frame
            call $wait-on-subtask
          end
        end
      else
        local.get $frame
        i32.const 1
        local.get $frame
        i32.load offset=40
        call $mode-error-code
        call $cleanup
      end
    else
      local.get $event
      i32.const 1
      i32.eq
      if (result i32)
        local.get $payload
        i32.const 2
        i32.eq
        if (result i32)
          local.get $frame
          i32.const 0
          i32.const 0
          call $cleanup
        else
          local.get $frame
          i32.const 1
          local.get $frame
          i32.load offset=40
          call $mode-error-code
          call $cleanup
        end
      else
        unreachable
        i32.const 0
      end
    end
  )

  (func (export "_initialize") (type $initialize))
)
