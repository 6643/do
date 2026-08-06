work = @host("do:generic-async-runtime-probe/host@0.1.0", "work", () -> nil)

run() -> nil {
    ready Future<nil> = work()
    @await(ready)
    pending Future<nil> = work()
    @cancel(pending)
}

start() {}
