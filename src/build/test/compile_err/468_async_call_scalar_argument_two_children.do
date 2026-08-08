work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(value u32) -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    first Future<nil> = @async(helper(7))
    second Future<nil> = @async(helper(7))
    @await(first)
    @await(second)
}
start() {}
