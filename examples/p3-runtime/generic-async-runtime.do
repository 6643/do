work = @host_async_func("do:generic-async-runtime-probe/host@0.1.0", "work", () -> nil)

run() -> nil {
    ready Future<nil> = work()
    @await(ready)
    middle Future<nil> = work()
    @await(middle)
    pending Future<nil> = work()
    @cancel(pending)
}

start() {}
