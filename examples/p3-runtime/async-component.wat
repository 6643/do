;; Generic Component Model host-callback probe. Its WIT surface is intentionally
;; not a WASI P3 interface; P3 binding has a separate compatibility gate.
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
    (import "host" "next-event" (func $next-event (result i32)))
    (func (export "run") (result i32)
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
