(module
  (type $read (func (result i32)))
  (type $future-read (func (param i32 i32) (result i32)))
  (type $future-cancel-read (func (param i32) (result i32)))
  (type $future-drop-readable (func (param i32)))
  (type $ticket-drop (func (param i32)))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $waitable-set-drop (func (param i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $async-run (func (param i32) (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $task-return (func))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (type $initialize (func))

  (import "do:future-owned-canonical/source@0.1.0" "read" (func $read (type $read)))
  (import "do:future-owned-canonical/source@0.1.0" "[async-lower][future-read-0]read" (func $future-read (type $future-read)))
  (import "do:future-owned-canonical/source@0.1.0" "[async-lower][future-cancel-read-0]read" (func $future-cancel-read (type $future-cancel-read)))
  (import "do:future-owned-canonical/source@0.1.0" "[future-drop-readable-0]read" (func $future-drop-readable (type $future-drop-readable)))
  (import "do:future-owned-canonical/source@0.1.0" "[resource-drop]ticket" (func $ticket-drop (type $ticket-drop)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
  (import "$root" "[context-get-0]" (func $context-get (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set (type $context-set)))
  (import "[export]do:future-owned-canonical/probe@0.1.0" "[task-return]run" (func $task-return (type $task-return)))

  (memory (export "memory") 1)
  ;; Frame: 0 waitable-set, 4 future reader, 8 mode, 12 payload, 16 ticket, 20 ticket-present.
  (global $frame-next (mut i32) (i32.const 1024))

  (func $layout-markers
    ;; [future-owned-payload]
    i32.const 12
    drop
    ;; [future-owned-ticket-present]
    i32.const 20
    drop
  )

  (func $frame-alloc (result i32)
    global.get $frame-next
    global.get $frame-next
    i32.const 32
    i32.add
    global.set $frame-next
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    i32.const 32
    i32.add
    global.get $frame-next
    i32.ne
    if
      unreachable
    end
    local.get $frame
    global.set $frame-next
  )

  (func $drop-future (param $frame i32) (local $future i32)
    local.get $frame
    i32.const 4
    i32.add
    i32.load
    local.tee $future
    i32.eqz
    if
      return
    end
    local.get $future
    call $future-drop-readable
    local.get $frame
    i32.const 4
    i32.add
    i32.const 0
    i32.store
  )

  (func $release-ticket (param $frame i32) (local $ticket i32)
    ;; [future-owned-resource-drop]
    local.get $frame
    i32.const 20
    i32.add
    i32.load
    i32.eqz
    if
      return
    end
    local.get $frame
    i32.const 20
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 16
    i32.add
    i32.load
    local.set $ticket
    local.get $frame
    i32.const 16
    i32.add
    i32.const 0
    i32.store
    local.get $ticket
    call $ticket-drop
  )

  (func $cleanup (param $frame i32) (result i32)
    local.get $frame
    call $drop-future
    local.get $frame
    call $release-ticket
    local.get $frame
    i32.load
    call $waitable-set-drop
    i32.const 0
    call $context-set
    call $task-return
    local.get $frame
    call $frame-free
    i32.const 0
  )

  (func $wait-on-read (param $frame i32) (result i32)
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

  (func $accept-read (param $frame i32) (param $payload i32) (result i32) (local $ticket i32)
    local.get $frame
    i32.const 12
    i32.add
    local.get $payload
    i32.load
    i32.store
    local.get $frame
    i32.const 12
    i32.add
    i32.load
    local.set $ticket
    local.get $frame
    i32.const 12
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 16
    i32.add
    local.get $ticket
    i32.store
    local.get $frame
    i32.const 20
    i32.add
    i32.const 1
    i32.store
    ;; [future-owned-transfer]
    ;; [mode-after-resource-transfer]
    local.get $frame
    call $cleanup
  )

  (func $accept-read-callback (param $frame i32) (param $code i32) (result i32)
    local.get $code
    i32.const 2
    i32.eq
    if (result i32)
      local.get $frame
      call $cleanup
    else
      local.get $code
      i32.eqz
      if (result i32)
        local.get $frame
        local.get $frame
        i32.const 12
        i32.add
        call $accept-read
      else
        unreachable
        i32.const 0
      end
    end
  )

  (func $start-read (param $frame i32) (result i32) (local $future i32) (local $code i32)
    call $read
    local.tee $future
    i32.eqz
    if
      unreachable
    end
    local.get $frame
    i32.const 4
    i32.add
    local.get $future
    i32.store
    local.get $future
    local.get $frame
    i32.const 12
    i32.add
    call $future-read
    local.tee $code
    i32.const -1
    i32.eq
    if (result i32)
      local.get $frame
      i32.const 8
      i32.add
      i32.load
      i32.const 2
      i32.eq
      if (result i32)
        local.get $future
        call $future-cancel-read
        ;; [future-owned-cancel]
        local.tee $code
        i32.const -1
        i32.eq
        if (result i32)
          local.get $frame
          call $wait-on-read
        else
          local.get $frame
          call $cleanup
        end
      else
        local.get $frame
        call $wait-on-read
      end
    else
      local.get $frame
      local.get $frame
      i32.const 12
      i32.add
      call $accept-read
    end
  )

  (func (export "[async-lift]do:future-owned-canonical/probe@0.1.0#run") (type $async-run) (param $mode i32) (result i32) (local $frame i32)
    call $frame-alloc
    local.tee $frame
    call $context-set
    local.get $frame
    call $waitable-set-new
    i32.store
    local.get $frame
    i32.const 4
    i32.add
    i32.const 0
    i32.store
    local.get $frame
    i32.const 8
    i32.add
    local.get $mode
    i32.store
    local.get $frame
    i32.const 12
    i32.add
    i32.const 0
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
    call $start-read
  )

  (func (export "[callback][async-lift]do:future-owned-canonical/probe@0.1.0#run") (type $async-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    call $context-get
    local.set $frame
    local.get $event
    i32.const 4
    i32.eq
    if (result i32)
      local.get $frame
      local.get $payload
      call $accept-read-callback
    else
      unreachable
      i32.const 0
    end
  )

  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable
  )
  (func (export "_initialize") (type $initialize))
)
