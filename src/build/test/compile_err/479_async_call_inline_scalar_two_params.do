work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(first u32, second u32) -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    helper(7, 8)
    child Future<nil> = @async(helper(7, 8))
    @await(child)
}
start() {}
