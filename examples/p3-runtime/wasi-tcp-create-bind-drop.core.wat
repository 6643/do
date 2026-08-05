(module
  ;; socket-target protocol=tcp
  ;; socket-layout result-tag=0 result-payload=4 address=0..40
  (type $create (func (param i32 i32)))
  (type $bind (func (param i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32 i32)))
  (type $drop (func (param i32)))
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (import "wasi:sockets/types@0.3.0" "[static]tcp-socket.create" (func $tcp-create (type $create)))
  (import "wasi:sockets/types@0.3.0" "[method]tcp-socket.bind" (func $tcp-bind (type $bind)))
  (import "wasi:sockets/types@0.3.0" "[resource-drop]tcp-socket" (func $tcp-drop (type $drop)))
  (memory (export "memory") 1)
  (global $__wasi_result_area_base i32 (i32.const 1024))
  (global $cabi-heap (mut i32) (i32.const 2048))
  ;; canonical IPv4 bind args: tag=0, port=0, address=127.0.0.1
  (func (export "run") (result i32) (local $socket i32)
    i32.const 0
    global.get $__wasi_result_area_base
    call $tcp-create
    global.get $__wasi_result_area_base
    i32.load
    i32.eqz
    if (result i32)
      global.get $__wasi_result_area_base
      i32.const 4
      i32.add
      i32.load
      local.set $socket
      local.get $socket
      i32.const 0
      i32.const 0
      i32.const 127
      i32.const 0
      i32.const 0
      i32.const 1
      i32.const 0
      i32.const 0
      i32.const 0
      i32.const 0
      i32.const 0
      i32.const 0
      global.get $__wasi_result_area_base
      call $tcp-bind
      global.get $__wasi_result_area_base
      i32.load
      i32.eqz
      if
        local.get $socket
        call $tcp-drop
        i32.const 1
        return
      end
      local.get $socket
      call $tcp-drop
      i32.const 2
      return
    else
      i32.const 0
    end
  )
  (func (export "cabi_post_run") (param i32))
  (func (export "cabi_realloc") (type $cabi-realloc)
    global.get $cabi-heap
    global.get $cabi-heap
    local.get 3
    i32.add
    global.set $cabi-heap
  )
  (func (export "_initialize"))
)
