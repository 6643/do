work = @host_async_func("do:generic-async-probe/host@0.1.0", "work", () -> nil)

run() -> nil {
    payload Future<i32> = @async(work())
    @await(payload)
    pending Future<nil> = @async(work())
    @cancel(pending)
}

start() {}
