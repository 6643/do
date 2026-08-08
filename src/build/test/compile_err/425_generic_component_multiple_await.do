work = @host_async_func("do:generic-async-probe/host@0.1.0", "work", () -> nil)

run() -> nil {
    first Future<nil> = @async(work())
    @await(first)
    second Future<nil> = @async(work())
    @await(second)
    third Future<nil> = @async(work())
    @await(third)
    pending Future<nil> = @async(work())
    @cancel(pending)
}

start() {}
