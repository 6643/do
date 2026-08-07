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

  (import "do:g6-2-batched-list-producer/types@0.1.0" "[resource-drop]ticket"
    (func $ticket-drop (type $resource-drop)))
  (import "do:g6-2-batched-list-producer/source@0.1.0" "make-ticket"
    (func $make-ticket (type $make-ticket)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[async-lower]consume-via-stream"
    (func $sink-call (type $async-lower)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[stream-new-0]consume-via-stream"
    (func $stream-new (type $stream-new)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[stream-cancel-read-0]consume-via-stream"
    (func $stream-cancel-read (type $stream-cancel)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[stream-cancel-write-0]consume-via-stream"
    (func $stream-cancel-write (type $stream-cancel)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[stream-drop-readable-0]consume-via-stream"
    (func $stream-drop-readable (type $stream-drop)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[stream-drop-writable-0]consume-via-stream"
    (func $stream-drop-writable (type $stream-drop)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[async-lower][stream-read-0]consume-via-stream"
    (func $stream-read (type $stream-io)))
  (import "do:g6-2-batched-list-producer/sink@0.1.0" "[async-lower][stream-write-0]consume-via-stream"
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
  ;; 16 writable, 20/44 batch ownership states, 24/48 list pointers,
  ;; 28/52 list lengths, 32 sink subtask, 36 pending batch, 40 mode,
  ;; 64/68 and 72/76 list pointer/length pairs passed to stream-write.
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
    ;; [producer-list-pointer-batch-1]
    i32.const 72
    drop
    ;; [producer-list-length-batch-1]
    i32.const 76
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

  ;; G6.2 private two-batch ownership helpers.
  (func $batch-drop-guest
    (param $frame i32) (param $ptr-off i32) (param $len-off i32)
    (local $index i32) (local $count i32) (local $handle i32)
    local.get $frame
    local.get $len-off
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
        local.get $ptr-off
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
          local.get $ptr-off
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

  (func $batch-free-list
    (param $frame i32) (param $ptr-off i32) (param $len-off i32)
    (param $list-off i32)
    (local $ptr i32) (local $count i32)
    local.get $frame
    local.get $ptr-off
    i32.add
    i32.load
    local.tee $ptr
    i32.eqz
    if
      return
    end
    local.get $frame
    local.get $len-off
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
    local.get $ptr-off
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    local.get $len-off
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    local.get $list-off
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    local.get $list-off
    i32.const 4
    i32.add
    i32.add
    i32.const 0
    i32.store
    global.get $list-release-count
    i32.const 1
    i32.add
    global.set $list-release-count
  )

  (func $batch-release
    (param $frame i32) (param $state-off i32) (param $ptr-off i32)
    (param $len-off i32) (param $list-off i32)
    (local $state i32)
    local.get $frame
    local.get $state-off
    i32.add
    i32.load
    local.tee $state
    i32.const 3
    i32.eq
    if
      return
    end
    local.get $state
    i32.const 1
    i32.eq
    if
      local.get $frame
      local.get $ptr-off
      local.get $len-off
      call $batch-drop-guest
      local.get $frame
      local.get $ptr-off
      local.get $len-off
      local.get $list-off
      call $batch-free-list
    end
    local.get $frame
    local.get $state-off
    i32.add
    i32.const 3
    i32.store
  )

  (func $batch-transfer
    (param $frame i32) (param $state-off i32) (param $ptr-off i32)
    (param $len-off i32) (param $list-off i32)
    (local $index i32) (local $count i32)
    local.get $frame
    local.get $state-off
    i32.add
    i32.load
    i32.const 1
    i32.eq
    if
      local.get $frame
      local.get $len-off
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
          local.get $ptr-off
          i32.add
          i32.load
          local.get $index
          i32.const 4
          i32.mul
          i32.add
          i32.const 0
          i32.store
          local.get $index
          i32.const 1
          i32.add
          local.set $index
          br $loop
        end
      end
      local.get $frame
      local.get $ptr-off
      local.get $len-off
      local.get $list-off
      call $batch-free-list
      local.get $frame
      local.get $state-off
      i32.add
      i32.const 2
      i32.store
    end
  )

  (func $make-batch0 (param $frame i32) (result i32)
    (local $ptr i32) (local $handle i32)
    i32.const 0
    i32.const 0
    i32.const 4
    i32.const 8
    call $cabi-realloc
    local.set $ptr
    local.get $frame
    i32.const 24
    i32.add
    local.get $ptr
    i32.store
    local.get $frame
    i32.const 28
    i32.add
    i32.const 2
    i32.store
    local.get $frame
    i32.const 64
    i32.add
    local.get $ptr
    i32.store
    local.get $frame
    i32.const 68
    i32.add
    i32.const 2
    i32.store
    local.get $frame
    i32.const 20
    i32.add
    i32.const 1
    i32.store
    local.get $ptr
    i32.const 0
    i32.store
    local.get $ptr
    i32.const 4
    i32.add
    i32.const 0
    i32.store
    i32.const 111
    call $make-ticket
    local.tee $handle
    i32.eqz
    if
      i32.const -1
      return
    end
    local.get $ptr
    local.get $handle
    i32.store
    i32.const 222
    call $make-ticket
    local.tee $handle
    i32.eqz
    if
      i32.const -1
      return
    end
    local.get $ptr
    i32.const 4
    i32.add
    local.get $handle
    i32.store
    i32.const 0
  )

  (func $make-batch1 (param $frame i32) (result i32)
    (local $ptr i32) (local $handle i32)
    i32.const 0
    i32.const 0
    i32.const 4
    i32.const 4
    call $cabi-realloc
    local.set $ptr
    local.get $frame
    i32.const 48
    i32.add
    local.get $ptr
    i32.store
    local.get $frame
    i32.const 52
    i32.add
    i32.const 1
    i32.store
    local.get $frame
    i32.const 72
    i32.add
    local.get $ptr
    i32.store
    local.get $frame
    i32.const 76
    i32.add
    i32.const 1
    i32.store
    local.get $frame
    i32.const 44
    i32.add
    i32.const 1
    i32.store
    local.get $ptr
    i32.const 0
    i32.store
    i32.const 333
    call $make-ticket
    local.tee $handle
    i32.eqz
    if
      i32.const -1
      return
    end
    local.get $ptr
    local.get $handle
    i32.store
    i32.const 0
  )

  (func $cleanup-batched
    (param $frame i32) (param $tag i32) (param $payload i32) (result i32)
    ;; [producer-batch-child-before-parent-cleanup]
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
    i32.const 20
    i32.const 24
    i32.const 28
    i32.const 64
    call $batch-release
    local.get $frame
    i32.const 44
    i32.const 48
    i32.const 52
    i32.const 72
    call $batch-release
    ;; [producer-batch-list-release]
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

  (func $finish-batched
    (param $frame i32) (param $tag i32) (param $payload i32) (result i32)
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
    i32.const 32
    i32.add
    i32.load
    i32.eqz
    if (result i32)
      local.get $frame
      local.get $tag
      local.get $payload
      call $cleanup-batched
    else
      local.get $frame
      call $wait-on-subtask
    end
  )

  (func $write-batched (param $frame i32) (param $batch i32) (result i32)
    (local $status i32)
    ;; [producer-batch-0]
    ;; [producer-batch-1]
    local.get $frame
    i32.const 16
    i32.add
    i32.load
    local.get $batch
    i32.eqz
    if (result i32)
      local.get $frame
      i32.const 64
      i32.add
    else
      local.get $frame
      i32.const 72
      i32.add
    end
    i32.const 1
    call $stream-write
    local.set $status
    local.get $status
    i32.const 15
    i32.and
    i32.eqz
    if (result i32)
      local.get $batch
      i32.eqz
      if (result i32)
        local.get $frame
        i32.const 20
        i32.const 24
        i32.const 28
        i32.const 64
        call $batch-transfer
        ;; [producer-batch-transfer-0]
        local.get $frame
        i32.load offset=40
        i32.const 5
        i32.eq
        if (result i32)
          local.get $frame
          i32.load offset=32
          call $subtask-cancel
          drop
          local.get $frame
          i32.const 1
          i32.const 1
          call $cleanup-batched
        else
          local.get $frame
          i32.const 1
          call $write-batched
        end
      else
        local.get $frame
        i32.const 44
        i32.const 48
        i32.const 52
        i32.const 72
        call $batch-transfer
        ;; [producer-batch-transfer-1]
        local.get $frame
        i32.const 0
        i32.const 0
        call $finish-batched
      end
    else
      local.get $status
      i32.const -1
      i32.eq
      if (result i32)
        local.get $frame
        i32.const 36
        i32.add
        local.get $batch
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
          call $cleanup-batched
        else
          local.get $batch
          i32.eqz
          if (result i32)
            local.get $frame
            i32.const 20
            i32.const 24
            i32.const 28
            i32.const 64
            call $batch-transfer
            local.get $frame
            i32.const 1
            i32.const 1
            call $finish-batched
          else
            local.get $frame
            i32.const 44
            i32.const 48
            i32.const 52
            i32.const 72
            call $batch-transfer
            local.get $frame
            i32.const 1
            i32.const 1
            call $finish-batched
          end
        end
      end
    end
  )

  (func (export "[async-lift]produce") (type $async-run-u32) (param $mode i32) (result i32)
    (local $frame i32) (local $pair i64) (local $status i32) (local $subtask i32)
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
    local.get $mode
    i32.store offset=40
    local.get $frame
    i32.const 0
    i32.store offset=44
    local.get $frame
    i32.const 0
    i32.store offset=48
    local.get $frame
    i32.const 0
    i32.store offset=52
    local.get $frame
    i32.const 0
    i32.store offset=64
    local.get $frame
    i32.const 0
    i32.store offset=68
    local.get $frame
    i32.const 0
    i32.store offset=72
    local.get $frame
    i32.const 0
    i32.store offset=76
    local.get $frame
    call $make-batch0
    local.set $status
    local.get $status
    i32.eqz
    if
    else
      local.get $frame
      i32.const 1
      i32.const 2
      call $cleanup-batched
      return
    end
    local.get $frame
    call $make-batch1
    local.set $status
    local.get $status
    i32.eqz
    if
    else
      local.get $frame
      i32.const 1
      i32.const 2
      call $cleanup-batched
      return
    end
    call $stream-new
    local.set $pair
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
      call $cleanup-batched
      return
    end
    local.get $frame
    i32.const 0
    call $write-batched
  )

  (func (export "[callback][async-lift]produce") (type $async-callback)
    (param $event i32) (param $index i32) (param $payload i32) (result i32)
    (local $frame i32) (local $batch i32)
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
        i32.const 36
        i32.add
        i32.load
        local.set $batch
        local.get $batch
        i32.eqz
        if (result i32)
          local.get $frame
          i32.const 20
          i32.const 24
          i32.const 28
          i32.const 64
          call $batch-transfer
          ;; [producer-batch-transfer-0]
          local.get $frame
          i32.load offset=40
          i32.const 5
          i32.eq
          if (result i32)
            local.get $frame
            i32.load offset=32
            call $subtask-cancel
            drop
            local.get $frame
            i32.const 1
            i32.const 1
            call $cleanup-batched
          else
            local.get $frame
            i32.const 1
            call $write-batched
          end
        else
          local.get $frame
          i32.const 44
          i32.const 48
          i32.const 52
          i32.const 72
          call $batch-transfer
          ;; [producer-batch-transfer-1]
          local.get $frame
          i32.const 0
          i32.const 0
          call $finish-batched
        end
      else
        local.get $frame
        i32.const 1
        i32.const 1
        call $cleanup-batched
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
          call $cleanup-batched
        else
          local.get $frame
          i32.const 1
          i32.const 1
          call $cleanup-batched
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
        i32.const 0
      else
        unreachable
        i32.const 0
      end
    end
  )

  (func (export "_initialize") (type $initialize))
)
