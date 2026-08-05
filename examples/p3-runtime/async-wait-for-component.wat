;; Exact Preview 3 import probe. The core wrapper is deliberately minimal: it
;; calls the import and returns only after the wait has completed.
(component
  (type $monotonic-clock
    (instance
      (export "wait-for" (func $wait-for async (param "how-long" u64)))
    )
  )
  (import "wasi:clocks/monotonic-clock@0.3.0"
    (instance $clock (type $monotonic-clock)))

  (alias export $clock "wait-for" (func $wait-for))
  (core func $task-return (canon task.return))
  (core func $wait-for-lower (canon lower (func $wait-for)))
  (core module $guest
    (import "" "task.return" (func $task-return))
    (import "" "wait-for" (func $wait-for (param i64)))
    (func (export "run") (param i64) (result i32)
      local.get 0
      call $wait-for
      call $task-return
      i32.const 0
    )
    (func (export "run-callback") (param i32 i32 i32) (result i32)
      unreachable
    )
  )
  (core instance $guest-instance
    (instantiate $guest
      (with "" (instance
        (export "task.return" (func $task-return))
        (export "wait-for" (func $wait-for-lower))
      ))
    )
  )
  (func $run async (param "how-long" u64)
    (canon lift (core func $guest-instance "run") async
      (callback (func $guest-instance "run-callback")))
  )
  (export "run" (func $run))
)
