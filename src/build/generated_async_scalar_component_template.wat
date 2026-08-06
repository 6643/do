(module
  (type $completion (func (result i32)))
  (type $future-read (func (param i32 i32) (result i32)))
  (type $future-cancel-read (func (param i32) (result i32)))
  (type $future-drop-readable (func (param i32)))
  (type $waitable-set-new (func (result i32)))
  (type $waitable-join (func (param i32 i32)))
  (type $waitable-set-drop (func (param i32)))
  (type $context-get (func (result i32)))
  (type $context-set (func (param i32)))
  (type $async-run (func (result i32)))
  (type $async-callback (func (param i32 i32 i32) (result i32)))
  (type $task-return (func))
  (type $task-cancel (func))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))

  (import "__ASYNC_IMPORT_MODULE__" "__ASYNC_COMPLETION__"
    (func $completion (type $completion)))
  (import "__ASYNC_IMPORT_MODULE__" "__ASYNC_IMPORT_NAME__"
    (func $future-read (type $future-read)))
  (import "__ASYNC_IMPORT_MODULE__" "[async-lower][future-cancel-read-0]__ASYNC_COMPLETION__"
    (func $future-cancel-read (type $future-cancel-read)))
  (import "__ASYNC_IMPORT_MODULE__" "[future-drop-readable-0]__ASYNC_COMPLETION__"
    (func $future-drop-readable (type $future-drop-readable)))
  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
  (import "$root" "[context-get-0]" (func $context-get (type $context-get)))
  (import "$root" "[context-set-0]" (func $context-set (type $context-set)))
  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-cancel)))
  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))

  (memory (export "memory") 1)
  ;; Frame: waitable-set @0, future reader @4, state @8, scalar payload @__PAYLOAD_OFFSET__.
  ;; [scalar-payload] offset=__PAYLOAD_OFFSET__ byte-size=__PAYLOAD_BYTE_SIZE__ alignment=__PAYLOAD_ALIGNMENT__ encoding=__PAYLOAD_ENCODING__
  (global $frame-next (mut i32) (i32.const 1024))

  (func $frame-alloc (result i32) (local $frame i32)
    global.get $frame-next
    local.tee $frame
    i32.const 32
    i32.add
    global.set $frame-next
    local.get $frame
  )

  (func $frame-free (param $frame i32)
    local.get $frame
    global.set $frame-next
  )

  (func $drop-readable (param $frame i32) (local $future i32)
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

  (func $cleanup (param $frame i32) (result i32)
    local.get $frame
    call $drop-readable
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

  (func $wait-on-completion (param $frame i32) (result i32)
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

  (func $finish-cancel (param $frame i32) (param $code i32) (result i32)
    local.get $code
    i32.const 0
    i32.eq
    local.get $code
    i32.const 2
    i32.eq
    i32.or
    if (result i32)
      local.get $frame
      call $cleanup
    else
      unreachable
      i32.const 0
    end
  )

  (func $start-second (param $frame i32) (result i32) (local $future i32) (local $code i32)
    ;; [async-scalar] cancel
    local.get $frame
    i32.const 8
    i32.add
    i32.const 1
    i32.store
    call $completion
    local.set $future
    local.get $frame
    i32.const 4
    i32.add
    local.get $future
    i32.store
    local.get $future
    local.get $frame
    i32.const __PAYLOAD_OFFSET__
    i32.add
    call $future-read
    local.tee $code
    i32.const -1
    i32.eq
    if (result i32)
      local.get $future
      call $future-cancel-read
      local.tee $code
      i32.const -1
      i32.eq
      if (result i32)
        local.get $frame
        call $wait-on-completion
      else
        local.get $frame
        local.get $code
        call $finish-cancel
      end
    else
      local.get $frame
      local.get $code
      call $finish-cancel
    end
  )

  (func $accept-first (param $frame i32) (param $payload i32) (result i32)
    local.get $payload
    i32.eqz
    if
    else
      ;; [scalar-payload-load] one ready scalar payload read
      ;; [scalar-payload-store] one frame payload store
      local.get $frame
      i32.const __PAYLOAD_OFFSET__
      i32.add
      local.get $payload
      __PAYLOAD_LOAD__
      __PAYLOAD_STORE__
    end
    local.get $frame
    call $drop-readable
    local.get $frame
    call $start-second
  )

  (func $start-first (param $frame i32) (result i32) (local $future i32) (local $code i32)
    call $completion
    local.set $future
    local.get $frame
    i32.const 4
    i32.add
    local.get $future
    i32.store
    local.get $future
    local.get $frame
    i32.const __PAYLOAD_OFFSET__
    i32.add
    call $future-read
    local.tee $code
    i32.const -1
    i32.eq
    if (result i32)
      ;; [async-scalar] pending
      local.get $frame
      call $wait-on-completion
    else
      ;; [async-scalar] ready
      local.get $frame
      local.get $frame
      i32.const __PAYLOAD_OFFSET__
      i32.add
      call $accept-first
    end
  )

  (func (export "[async-lift]run") (type $async-run) (result i32) (local $frame i32)
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
    i32.const 0
    i32.store
    local.get $frame
    i32.const __PAYLOAD_OFFSET__
    i32.add
    __PAYLOAD_ZERO__
    __PAYLOAD_STORE__
    local.get $frame
    call $start-first
  )

  (func (export "[callback][async-lift]run") (type $async-callback)
    (local $frame i32)
    call $context-get
    local.set $frame
    local.get 0
    i32.const 4
    i32.eq
    if (result i32)
      local.get $frame
      i32.const 8
      i32.add
      i32.load
      i32.eqz
      if (result i32)
        local.get $frame
        local.get 2
        call $accept-first
      else
        local.get $frame
        call $drop-readable
        local.get $frame
        call $cleanup
      end
    else
      unreachable
      i32.const 0
    end
  )

  (func (export "cabi_realloc") (type $cabi-realloc)
    unreachable
  )
  (func (export "_initialize"))
)
