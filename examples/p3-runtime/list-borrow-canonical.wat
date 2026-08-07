(module
  (type $read (func (param i32 i32) (result i32)))
  (type $drop (func (param i32)))
  (type $run (func (param i32 i32) (result i32)))

  (import "do:list-borrow-canonical/api@0.1.0" "read" (func $read (type $read)))
  (import "do:list-borrow-canonical/api@0.1.0" "[resource-drop]ticket" (func $ticket-drop (type $drop)))

  (memory (export "memory") 1)

  (global $list-ptr i32 (i32.const 64))
  (global $list-stride i32 (i32.const 4))

  (func $borrow-list-layout-markers
    ;; [borrow-list-pointer]
    i32.const 64
    drop
    ;; [borrow-list-element-stride]
    i32.const 4
    drop
  )

  (func (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    i32.const 64
  )

  (func (export "run") (type $run) (param $ticket i32) (param $mode i32) (result i32)
    (local $result i32)
    local.get $mode
    i32.eqz
    if (result i32)
      i32.const 0
      i32.const 0
      call $read
    else
      global.get $list-ptr
      local.get $ticket
      i32.store
      local.get $mode
      i32.const 3
      i32.eq
      if
        global.get $list-ptr
        i32.const 4
        i32.add
        local.get $ticket
        i32.store
        global.get $list-ptr
        i32.const 8
        i32.add
        local.get $ticket
        i32.store
      end
      global.get $list-ptr
      local.get $mode
      call $read
    end
    local.set $result
    local.get $ticket
    call $ticket-drop
    local.get $result
  )
)
