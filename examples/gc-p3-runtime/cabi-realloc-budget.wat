(module
  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
  (memory 1 2)
  (global $async-byte-budget-used (mut i64) (i64.const 0))
  (global $async-byte-budget-limit (mut i64) (i64.const -1))
  (global $heap-next (mut i32) (i32.const 65536))

  (func (export "[async-config]byte-budget-limit") (param $limit i64) (result i32)
    local.get $limit
    i64.const -1
    i64.eq
    if (result i32)
      local.get $limit
      global.set $async-byte-budget-limit
      i32.const 1
    else
      local.get $limit
      i64.const 0
      i64.lt_s
      if (result i32)
        i32.const 0
      else
        global.get $async-byte-budget-used
        local.get $limit
        i64.gt_u
        if (result i32)
          i32.const 0
        else
          local.get $limit
          global.set $async-byte-budget-limit
          i32.const 1
        end
      end
    end
  )

  (func $async-byte-budget-reserve (param $bytes i64) (result i32)
    (local $next i64)
    global.get $async-byte-budget-used
    local.get $bytes
    i64.add
    local.tee $next
    global.get $async-byte-budget-used
    i64.lt_u
    if (result i32)
      i32.const 0
    else
      global.get $async-byte-budget-limit
      i64.const -1
      i64.eq
      if (result i32)
        i32.const 1
      else
        local.get $next
        global.get $async-byte-budget-limit
        i64.le_u
      end
      if (result i32)
        local.get $next
        global.set $async-byte-budget-used
        i32.const 1
      else
        i32.const 0
      end
    end
  )

  (func $async-byte-budget-release (param $bytes i64)
    global.get $async-byte-budget-used
    local.get $bytes
    i64.lt_u
    if unreachable end
    global.get $async-byte-budget-used
    local.get $bytes
    i64.sub
    global.set $async-byte-budget-used
  )

  (func $cabi_realloc_try
    (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (param $trap i32)
    (result i32)
    (local $ptr i32)
    (local $end i32)
    (local $budget-delta i64)
    local.get $size
    local.get $old-size
    i32.gt_u
    if
      local.get $size
      local.get $old-size
      i32.sub
      i64.extend_i32_u
      local.tee $budget-delta
      call $async-byte-budget-reserve
      i32.eqz
      if
        local.get $trap
        if unreachable end
        i32.const -1
        return
      end
    else
      local.get $old-size
      local.get $size
      i32.gt_u
      if
        local.get $old-size
        local.get $size
        i32.sub
        i64.extend_i32_u
        call $async-byte-budget-release
      end
    end
    global.get $heap-next
    local.set $ptr
    local.get $ptr
    local.get $size
    i32.add
    local.set $end
    local.get $end
    memory.size
    i32.const 16
    i32.shl
    i32.gt_u
    if
      local.get $end
      i32.const 65535
      i32.add
      i32.const 16
      i32.shr_u
      memory.size
      i32.sub
      memory.grow
      i32.const -1
      i32.eq
      if
        local.get $budget-delta
        call $async-byte-budget-release
        local.get $trap
        if unreachable end
        i32.const -1
        return
      end
    end
    local.get $end
    global.set $heap-next
    local.get $ptr
  )

  (func $cabi_realloc (export "cabi_realloc") (type $cabi-realloc)
    (param $old i32) (param $old-size i32) (param $align i32) (param $size i32)
    (result i32)
    local.get $old
    local.get $old-size
    local.get $align
    local.get $size
    i32.const 1
    call $cabi_realloc_try
  )

  (func (export "probe") (result i32) (local $ptr i32)
    i64.const 12
    call 0
    drop
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 8
    call $cabi_realloc
    local.set $ptr
    local.get $ptr
    i32.const 8
    i32.const 1
    i32.const 4
    call $cabi_realloc
    drop
    global.get $async-byte-budget-used
    i32.wrap_i64
  )

  (func (export "rollback_probe") (result i32) (local $status i32)
    i64.const -1
    call 0
    drop
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 131073
    i32.const 0
    call $cabi_realloc_try
    local.set $status
    local.get $status
    i32.const -1
    i32.eq
    if
      global.get $async-byte-budget-used
      i32.wrap_i64
      i32.eqz
      if
        global.get $heap-next
        i32.const 65536
        i32.eq
        if
          i32.const 1
          return
        end
      end
    end
    i32.const 0
  )

  (func (export "quota_reject") (result i32)
    i64.const 4
    call 0
    drop
    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 8
    call $cabi_realloc
    drop
    i32.const 0
  )
)
