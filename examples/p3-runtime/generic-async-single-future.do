work = @host("do:generic-async-probe/host@0.1.0", "work", () -> nil)

run() -> nil {
    ready Future<nil> = @async(work())
    @await(ready)
    middle Future<nil> = @async(work())
    @await(middle)
    pending Future<nil> = @async(work())
    @cancel(pending)
}

start() {}
