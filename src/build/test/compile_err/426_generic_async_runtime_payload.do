work = @host("do:generic-async-runtime-probe/host@0.1.0", "work", () -> nil)

run() -> nil {
    payload Future<i32> = work()
    @await(payload)
    pending Future<nil> = work()
    @cancel(pending)
}

start() {}
