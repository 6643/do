;; Core GC async-frame ownership probe. The table is the guest root; the host
;; would retain only the i32 slot handle across a suspension.
(module
  (type $frame (struct
    (field $saved i32)
    (field $state (mut i32))
  ))
  (type $free-slot (struct
    (field $handle i32)
    (field $next (ref null $free-slot))
  ))
  (table $frames 0 (ref null $frame))
  (memory 0)
  (global $free-head (mut (ref null $free-slot)) (ref.null $free-slot))
  ;; The probe uses a fixed 16-byte instance budget: two 8-byte frames fit,
  ;; while a third frame must be rejected before the table mutates.
  (global $budget-limit i32 (i32.const 16))
  (global $budget-used (mut i32) (i32.const 0))
  (global $canonical-next (mut i32) (i32.const 0))

  (func $budget-reserve (param $bytes i32) (result i32)
    global.get $budget-limit
    global.get $budget-used
    i32.sub
    local.get $bytes
    i32.ge_u
    if (result i32)
      global.get $budget-used
      local.get $bytes
      i32.add
      global.set $budget-used
      i32.const 1
    else
      i32.const 0
    end
  )

  (func $budget-release (param $bytes i32)
    global.get $budget-used
    local.get $bytes
    i32.ge_u
    if
      global.get $budget-used
      local.get $bytes
      i32.sub
      global.set $budget-used
    else
      unreachable
    end
  )

  (func $canonical-acquire (result i32)
    (local $ptr i32)
    (local $required i32)
    i32.const 8
    call $budget-reserve
    if (result i32)
      global.get $canonical-next
      local.tee $ptr
      i32.const 8
      i32.add
      local.tee $required
      memory.size
      i32.const 16
      i32.shl
      i32.gt_u
      if (result i32)
        i32.const 1
        memory.grow
        i32.const -1
        i32.eq
        if (result i32)
          i32.const 8
          call $budget-release
          i32.const -1
        else
          local.get $required
          global.set $canonical-next
          local.get $ptr
        end
      else
        local.get $required
        global.set $canonical-next
        local.get $ptr
      end
    else
      i32.const -1
    end
  )

  (func $canonical-release (param $ptr i32)
    local.get $ptr
    drop
    i32.const 8
    call $budget-release
  )

  (func $frame-alloc (param $frame (ref $frame)) (result i32)
    (local $handle i32)
    (local $node (ref $free-slot))
    i32.const 8
    call $budget-reserve
    if (result i32)
      global.get $free-head
      ref.is_null
      if (result i32)
        local.get $frame
        i32.const 1
        table.grow $frames
      else
        global.get $free-head
        ref.as_non_null
        local.tee $node
        struct.get $free-slot $next
        global.set $free-head
        local.get $node
        struct.get $free-slot $handle
      end
      local.set $handle
      local.get $handle
      i32.const -1
      i32.eq
      if
        i32.const 8
        call $budget-release
      else
        local.get $handle
        local.get $frame
        table.set $frames
      end
      local.get $handle
    else
      i32.const -1
    end
  )

  (func $start (param $value i32) (result i32)
    (local $frame (ref $frame))
    local.get $value
    i32.const 1
    struct.new $frame
    local.set $frame
    local.get $frame
    call $frame-alloc
  )

  (func $resume (param $handle i32) (result i32)
    (local $frame (ref $frame))
    local.get $handle
    table.get $frames
    ref.as_non_null
    local.set $frame
    local.get $frame
    i32.const 2
    struct.set $frame $state
    local.get $frame
    struct.get $frame $saved
  )

  (func $drop (param $handle i32)
    (local $node (ref $free-slot))
    local.get $handle
    ref.null $frame
    table.set $frames
    local.get $handle
    global.get $free-head
    struct.new $free-slot
    local.set $node
    local.get $node
    global.set $free-head
    i32.const 8
    call $budget-release
  )

  (func (export "budget_probe") (result i32)
    (local $first i32)
    (local $second i32)
    (local $rejected i32)
    i32.const 7
    call $start
    local.set $first
    i32.const 11
    call $start
    local.set $second
    i32.const 13
    call $start
    local.set $rejected
    local.get $rejected
    i32.const -1
    i32.eq
    if (result i32)
      local.get $first
      call $drop
      local.get $second
      call $drop
      global.get $budget-used
      i32.eqz
    else
      local.get $rejected
      call $drop
      local.get $first
      call $drop
      local.get $second
      call $drop
      i32.const 0
    end
  )

  (func (export "canonical_budget_probe") (result i32)
    (local $frame i32)
    (local $first i32)
    (local $second i32)
    i32.const 7
    call $start
    local.set $frame
    call $canonical-acquire
    local.set $first
    call $canonical-acquire
    local.set $second
    local.get $second
    i32.const -1
    i32.eq
    if (result i32)
      local.get $first
      call $canonical-release
      local.get $frame
      call $drop
      global.get $budget-used
      i32.eqz
      memory.size
      i32.const 1
      i32.ge_u
      i32.and
    else
      local.get $second
      call $canonical-release
      local.get $first
      call $canonical-release
      local.get $frame
      call $drop
      i32.const 0
    end
  )

  (func (export "probe") (result i32)
    (local $first i32)
    (local $second i32)
    (local $reused i32)
    i32.const 7
    call $start
    local.set $first
    i32.const 11
    call $start
    local.set $second
    local.get $first
    local.get $second
    i32.eq
    if unreachable end
    local.get $first
    call $resume
    i32.const 7
    i32.ne
    if unreachable end
    local.get $second
    call $resume
    i32.const 11
    i32.ne
    if unreachable end
    local.get $first
    call $drop
    i32.const 13
    call $start
    local.set $reused
    local.get $reused
    local.get $first
    i32.ne
    if unreachable end
    local.get $reused
    call $resume
    i32.const 13
    i32.ne
    if unreachable end
    local.get $reused
    call $drop
    local.get $second
    call $drop
    local.get $first
    table.get $frames
    ref.is_null
    i32.eqz
    if unreachable end
    local.get $second
    table.get $frames
    ref.is_null
    i32.eqz
    if unreachable end
    i32.const 27815
  )
)
