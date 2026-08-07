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
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (type $initialize (func))

  (import "do:g6-2-c-min-dynamic-producer/types@0.1.0" "[resource-drop]ticket"
    (func $ticket-drop (type $resource-drop)))
  (import "do:g6-2-c-min-dynamic-producer/source@0.1.0" "make-ticket"
    (func $make-ticket (type $make-ticket)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[async-lower]consume-via-stream"
    (func $sink-call (type $async-lower)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[stream-new-0]consume-via-stream"
    (func $stream-new (type $stream-new)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[stream-cancel-read-0]consume-via-stream"
    (func $stream-cancel-read (type $stream-cancel)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[stream-cancel-write-0]consume-via-stream"
    (func $stream-cancel-write (type $stream-cancel)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[stream-drop-readable-0]consume-via-stream"
    (func $stream-drop-readable (type $stream-drop)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[stream-drop-writable-0]consume-via-stream"
    (func $stream-drop-writable (type $stream-drop)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[async-lower][stream-read-0]consume-via-stream"
    (func $stream-read (type $stream-io)))
  (import "do:g6-2-c-min-dynamic-producer/sink@0.1.0" "[async-lower][stream-write-0]consume-via-stream"
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
  (global $heap-next (mut i32) (i32.const 65536))
  (global $last-list-ptr (mut i32) (i32.const 0))
  (global $last-list-size (mut i32) (i32.const 0))
  (global $list-release-count (mut i32) (i32.const 0))

  ;; Frame: 0 result tag, 4 result payload, 8 waitable set, 12 readable,
  ;; 16 writable, 20 ownership state, 24 list pointer, 28 list length,
  ;; 32 sink subtask, 36 pending-write state, 40 mode, 44 list element area.
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
    ;; [producer-list-pointer]
    i32.const 64
    drop
    ;; [producer-list-length]
    i32.const 68
    drop
    ;; [producer-list-element-stride]
    i32.const 4
    drop
    ;; [producer-list-ticket-offset]
    i32.const 0
    drop
    ;; [producer-stream-capacity]
    i32.const 1
    drop
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

  (func $drop-guest-tickets (param $frame i32)
    (local $index i32)
    (local $count i32)
    (local $handle i32)
    local.get $frame
    i32.const 28
    i32.add
    i32.load
    local.set $count
    i32.const 0
    local.set $index
    block $done
      loop $loop
        local.get $index
        local.get $count
        i32.ge_u
        br_if $done
        local.get $frame
        i32.const 24
        i32.add
        i32.load
        local.get $index
        i32.const 4
        i32.mul
        i32.add
        i32.load
        local.tee $handle
        i32.eqz
        if
        else
          local.get $handle
          call $ticket-drop
          local.get $frame
          i32.const 24
          i32.add
          i32.load
          local.get $index
          i32.const 4
          i32.mul
          i32.add
          i32.const 0
          i32.store
        end
        local.get $index
        i32.const 1
        i32.add
        local.set $index
        br $loop
      end
    end
  )

  (func $free-list (param $frame i32)
    (local $ptr i32)
    (local $count i32)
    local.get $frame
    i32.const 24
    i32.add
    i32.load
    local.tee $ptr
    i32.eqz
    if
      return
    end
    local.get $frame
    i32.const 28
    i32.add
    i32.load
    local.set $count
    local.get $ptr
    local.get $count
    i32.const 4
    i32.mul
    i32.const 4
    i32.const 0
    call $cabi-realloc
    drop
    local.get $frame
    i32.const 24
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 28
    i32.add
    i32.const 0
    i32.store
    global.get $list-release-count
    i32.const 1
    i32.add
    global.set $list-release-count
  )

  ;; Guest still owns the list while state=1. State=2 means the stream/host
  ;; owns every ticket and the guest must not call resource-drop.
  (func $release-guest-list (param $frame i32)
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
      call $drop-guest-tickets
      local.get $frame
      call $free-list
    end
    local.get $frame
    i32.const 20
    i32.add
    i32.const 3
    i32.store
  )

  (func $transfer-list (param $frame i32) (local $index i32)
    local.get $frame
    i32.const 20
    i32.add
    i32.load
    i32.const 1
    i32.eq
    if
      local.get $frame
      i32.const 28
      i32.add
      i32.load
      local.set $index
      block $clear-done
        loop $clear-loop
          local.get $index
          i32.eqz
          br_if $clear-done
          local.get $index
          i32.const 1
          i32.sub
          local.tee $index
          local.get $frame
          i32.const 24
          i32.add
          i32.load
          local.get $index
          i32.const 4
          i32.mul
          i32.add
          i32.const 0
          i32.store
          br $clear-loop
        end
      end
      local.get $frame
      call $free-list
      local.get $frame
      i32.const 20
      i32.add
      i32.const 2
      i32.store
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
    call $release-guest-list
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

  (func $make-list (param $frame i32) (param $mode i32) (result i32)
    (local $count i32)
    (local $ptr i32)
    (local $index i32)
    (local $handle i32)
    ;; The dynamic descriptor admits a bounded runtime length. Reject before
    ;; cabi_realloc or make-ticket so invalid input has no side effects.
    local.get $mode
    i32.const 3
    i32.gt_u
    if
      i32.const -1
      return
    end
    local.get $mode
    local.set $count
    i32.const 0
    i32.const 0
    i32.const 4
    local.get $count
    i32.const 4
    i32.mul
    call $cabi-realloc
    local.tee $ptr
    local.set $ptr
    local.get $frame
    i32.const 24
    i32.add
    local.get $ptr
    i32.store
    local.get $frame
    i32.const 28
    i32.add
    local.get $count
    i32.store
    local.get $frame
    i32.const 64
    i32.add
    local.get $ptr
    i32.store
    local.get $frame
    i32.const 68
    i32.add
    local.get $count
    i32.store
    local.get $frame
    i32.const 20
    i32.add
    i32.const 1
    i32.store
    i32.const 0
    local.set $index
    block $created
      loop $create-loop
        local.get $index
        local.get $count
        i32.ge_u
        br_if $created
        ;; [mode-before-ticket-3]
        local.get $index
        i32.const 1
        i32.add
        call $make-ticket
        local.tee $handle
        i32.eqz
        if
          i32.const -1
          return
        end
        local.get $ptr
        local.get $index
        i32.const 4
        i32.mul
        i32.add
        local.get $handle
        i32.store
        local.get $index
        i32.const 1
        i32.add
        local.set $index
        br $create-loop
      end
    end
    ;; [mode-after-list-create]
    local.get $frame
    i32.const 20
    i32.add
    i32.const 1
    i32.store
    i32.const 0
  )

  (func $write-list (param $frame i32) (result i32) (local $status i32)
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
      call $transfer-list
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
          i32.const 1
          call $cleanup
        else
          local.get $frame
          call $transfer-list
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
            i32.const 1
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
    call $make-list
    local.tee $status
    i32.eqz
    if
    else
      local.get $status
      i32.const -2
      i32.eq
      if (result i32)
        local.get $frame
        i32.const 1
        i32.const 0
        call $cleanup
      else
        local.get $frame
        i32.const 1
        i32.const 2
        call $cleanup
      end
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
    call $write-list
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
        call $transfer-list
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
      else
        local.get $frame
        i32.const 1
        i32.const 1
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
          i32.const 1
          call $cleanup
        end
      else
        unreachable
        i32.const 0
      end
    end
  )

  (func $cabi-realloc (export "cabi_realloc") (type $cabi-realloc)
    (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    (local $ptr i32)
    local.get $align
    i32.const 4
    i32.ne
    if
      unreachable
    end
    local.get $old
    i32.eqz
    if (result i32)
      local.get $size
      i32.eqz
      if (result i32)
        i32.const 0
      else
        local.get $size
        i32.const 4
        i32.eq
        local.get $size
        i32.const 8
        i32.eq
        i32.or
        local.get $size
        i32.const 12
        i32.eq
        i32.or
        if (result i32)
          global.get $heap-next
          local.tee $ptr
          local.get $size
          i32.add
          global.set $heap-next
          local.get $ptr
          global.set $last-list-ptr
          local.get $size
          global.set $last-list-size
          local.get $ptr
        else
          unreachable
          i32.const 0
        end
      end
    else
      local.get $size
      i32.eqz
      if (result i32)
        local.get $old
        global.get $last-list-ptr
        i32.ne
        if
          unreachable
        end
        local.get $old-size
        global.get $last-list-size
        i32.ne
        if
          unreachable
        end
        local.get $old
        global.set $last-list-ptr
        i32.const 0
        global.set $last-list-size
        i32.const 0
      else
        unreachable
        i32.const 0
      end
    end
  )

  (func (export "_initialize") (type $initialize))
)
