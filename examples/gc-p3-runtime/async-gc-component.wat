;; Component async host-callback probe with GC refs confined to the core module.
;; No GC ref crosses the component boundary: `run` returns only a canonical u32.
(component
  (type $host-events
    (instance
      (export "next-event" (func $next-event (result u32)))
    )
  )
  (import "do:component-async-probe/host-events@0.1.0"
    (instance $host (type $host-events)))

  (alias export $host "next-event" (func $next-event))
  (core func $next-event-lower (canon lower (func $next-event)))

  (core module $guest
    (type $value (struct (field $number i32)))
    (import "host" "next-event" (func $next-event (result i32)))
    (func (export "run") (result i32)
      (local $value (ref $value))
      i32.const 7
      struct.new $value
      local.set $value
      local.get $value
      struct.get $value $number
      i32.const 7
      i32.ne
      if
        unreachable
      end
      call $next-event
    )
  )
  (core instance $guest-instance
    (instantiate $guest
      (with "host" (instance
        (export "next-event" (func $next-event-lower))
      ))
    )
  )

  (func $run (result u32)
    (canon lift (core func $guest-instance "run"))
  )
  (export "run" (func $run))
)
