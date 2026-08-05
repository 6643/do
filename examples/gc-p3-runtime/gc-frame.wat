;; Core Wasm GC representation probe. This intentionally has no Component or
;; WASI imports: it proves only the GC instructions used by the future runtime.
(module
  ;; Source values are immutable GC objects. A source update must allocate a
  ;; replacement value instead of mutating an aliased source value.
  (type $value (struct
    (field $number i32)
  ))

  ;; Task/runtime-private data may use mutable fields.
  (type $frame (struct
    (field $state (mut i32))
    (field $current (mut (ref null $value)))
  ))

  ;; A queue is runtime-private mutable storage.
  (type $queue (array (mut i32)))

  ;; Returns 27815 when all operations below retain their expected values:
  ;;
  ;;   frame.state = 2
  ;;   source.value = 7
  ;;   rebuilt.value = 8
  ;;   queue values = [4, 5, 6]
  (func (export "probe") (result i32)
    (local $frame (ref $frame))
    (local $queue (ref $queue))
    (local $source (ref $value))
    (local $clone (ref $value))
    (local $rebuilt (ref $value))

    i32.const 1
    ref.null $value
    struct.new $frame
    local.set $frame

    i32.const 3
    array.new_default $queue
    local.set $queue

    local.get $queue
    i32.const 0
    i32.const 4
    array.set $queue

    local.get $queue
    i32.const 1
    i32.const 5
    array.set $queue

    local.get $queue
    i32.const 2
    i32.const 6
    array.set $queue

    i32.const 7
    struct.new $value
    local.set $source

    local.get $source
    struct.get $value $number
    struct.new $value
    local.set $clone

    local.get $clone
    struct.get $value $number
    i32.const 1
    i32.add
    struct.new $value
    local.set $rebuilt

    local.get $frame
    i32.const 2
    struct.set $frame $state

    local.get $frame
    local.get $rebuilt
    struct.set $frame $current

    local.get $frame
    struct.get $frame $state
    i32.const 10000
    i32.mul

    local.get $source
    struct.get $value $number
    i32.const 1000
    i32.mul
    i32.add

    local.get $frame
    struct.get $frame $current
    struct.get $value $number
    i32.const 100
    i32.mul
    i32.add

    local.get $queue
    i32.const 0
    array.get $queue
    local.get $queue
    i32.const 1
    array.get $queue
    i32.add
    local.get $queue
    i32.const 2
    array.get $queue
    i32.add
    i32.add

    i32.const 27815
    i32.ne
    if
      unreachable
    end

    i32.const 27815
  )
)
