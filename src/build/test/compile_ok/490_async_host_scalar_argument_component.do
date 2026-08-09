work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
helper(value u32) -> nil {
    pending Future<nil> = work(value)
    @await(pending)
}
run() -> nil {
    child Future<nil> = @async(helper(7))
    @await(child)
}
