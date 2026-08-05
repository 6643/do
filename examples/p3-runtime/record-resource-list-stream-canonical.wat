(module
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

  (import "do:record-resource-list-stream-canonical/source@0.1.0" "read-via-stream" (func $source-acquire (type $source-acquire)))
  (import "do:record-resource-list-stream-canonical/source@0.1.0" "[async-lower][stream-read-0]read-via-stream" (func $stream-read (type $stream-read)))
  (import "do:record-resource-list-stream-canonical/source@0.1.0" "[stream-drop-readable-0]read-via-stream" (func $stream-drop (type $drop)))
  (import "do:record-resource-list-stream-canonical/source@0.1.0" "[async-lower][future-read-1]read-via-stream" (func $future-read (type $future-read)))
  (import "do:record-resource-list-stream-canonical/source@0.1.0" "[future-drop-readable-1]read-via-stream" (func $future-drop (type $drop)))
  (import "do:record-resource-list-stream-canonical/source@0.1.0" "[resource-drop]ticket" (func $ticket-drop (type $drop)))
  (import "$root" "[waitable-set-new]" (func $waitable-new (type $waitable-new)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[waitable-set-drop]" (func $waitable-drop (type $waitable-drop)))
  (import "$root" "[context-get-0]" (func $context-get (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set (type $context-set)))
  (import "[export]do:record-resource-list-stream-canonical/probe@0.1.0" "[task-return]run" (func $task-return (type $task-return)))

  (memory (export "memory") 2)
  ;; Canonical list result area: pointer and length are two i32 words.
  ;; [list-result-alignment] 4
  ;; [list-frame-slot-base] 20

  (global $frame-next (mut i32) (i32.const 1024))
  (global $heap-next (mut i32) (i32.const 65536))
  (global $last-list-ptr (mut i32) (i32.const 0))
  (global $last-list-size (mut i32) (i32.const 0))

  ;; Frame: 0 waitable-set, 4 stream, 8 future, 12 phase,
  ;; 16 list-state, 20..31 owned handles, 64..71 raw list result,
  ;; 80 result tag, 84 result error code.
  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 128
    i32.add
    global.set $frame-next
  )
  (func $frame-free (param $frame i32)
    ;; The admitted source has one active frame; recycle it only after terminal cleanup.
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

  (func $list-layout-markers
    ;; [list-result-pointer]
    i32.const 64
    drop
    ;; [list-result-length]
    i32.const 68
    drop
    ;; [list-element-stride]
    i32.const 4
    drop
    ;; [list-ticket-offset]
    i32.const 0
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

  (func $release-list (param $frame i32) (local $count i32) (local $index i32) (local $handle i32)
    local.get $frame
    i32.const 16
    i32.add
    i32.load
    local.tee $count
    i32.const 2
    i32.eq
    if
      unreachable
    end
    local.get $count
    i32.eqz
    if
      return
    end
    i32.const 0
    local.set $index
    block $release-done
      loop $release-loop
        local.get $index
        local.get $count
        i32.ge_u
        br_if $release-done
        local.get $frame
        i32.const 20
        i32.add
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
          i32.const 20
          i32.add
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
        br $release-loop
      end
    end
    local.get $frame
    i32.const 16
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
    call $release-list
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

  (func $consume-list (param $frame i32) (local $ptr i32) (local $len i32) (local $index i32) (local $handle i32)
    ;; Validate pointer/length and allowed bounded lengths before loading a handle.
    local.get $frame
    i32.const 64
    i32.add
    i32.load
    local.set $ptr
    local.get $frame
    i32.const 68
    i32.add
    i32.load
    local.set $len
    local.get $len
    i32.eqz
    if
      local.get $ptr
      i32.eqz
      if
      else
        unreachable
      end
      global.get $last-list-ptr
      i32.eqz
      if
      else
        unreachable
      end
    else
      local.get $len
      i32.const 1
      i32.eq
      local.get $len
      i32.const 3
      i32.eq
      i32.or
      if
      else
        unreachable
      end
      local.get $ptr
      i32.eqz
      if
        unreachable
      end
      local.get $ptr
      i32.const 3
      i32.and
      i32.eqz
      if
      else
        unreachable
      end
      local.get $ptr
      global.get $last-list-ptr
      i32.eq
      if
      else
        unreachable
      end
      local.get $len
      i32.const 4
      i32.mul
      global.get $last-list-size
      i32.eq
      if
      else
        unreachable
      end
    end
    i32.const 0
    local.set $index
    block $consume-done
      loop $consume-loop
        local.get $index
        local.get $len
        i32.ge_u
        br_if $consume-done
        local.get $ptr
        local.get $index
        i32.const 4
        i32.mul
        i32.add
        i32.load
        local.tee $handle
        i32.eqz
        if
          unreachable
        end
        local.get $frame
        i32.const 20
        i32.add
        local.get $index
        i32.const 4
        i32.mul
        i32.add
        local.get $handle
        i32.store
        local.get $ptr
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
        br $consume-loop
      end
    end
    local.get $frame
    i32.const 16
    i32.add
    local.get $len
    i32.store
    local.get $ptr
    local.get $len
    i32.const 4
    i32.mul
    i32.const 4
    i32.const 0
    call $cabi-realloc
    drop
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

  (func $accept-stream (param $frame i32) (param $code i32) (result i32)
    local.get $code
    i32.const 16
    i32.eq
    if (result i32)
      ;; [mode-before-list-consume]
      local.get $frame
      call $consume-list
      ;; [mode-after-list-consume]
      local.get $frame
      call $start-completion
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

  (func (export "[async-lift]do:record-resource-list-stream-canonical/probe@0.1.0#run") (type $async-run) (result i32) (local $frame i32)
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

  (func (export "[callback][async-lift]do:record-resource-list-stream-canonical/probe@0.1.0#run") (type $async-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
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

  (func $cabi-realloc (export "cabi_realloc") (type $cabi-realloc) (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32) (local $ptr i32)
    local.get $align
    i32.const 4
    i32.eq
    if
    else
      unreachable
    end
    local.get $old
    i32.eqz
    if (result i32)
      local.get $size
      i32.const 0
      i32.eq
      if (result i32)
        i32.const 0
      else
        local.get $size
        i32.const 4
        i32.eq
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
        i32.eq
        if
        else
          unreachable
        end
        local.get $old-size
        global.get $last-list-size
        i32.eq
        if
        else
          unreachable
        end
        ;; The validated list is the last admitted backing allocation, so release reclaims it.
        local.get $old
        local.get $old-size
        i32.add
        global.get $heap-next
        i32.eq
        if
        else
          unreachable
        end
        local.get $old
        global.set $heap-next
        i32.const 0
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
