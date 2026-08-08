work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(value u32) -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    selected u32 = 7
    helper(selected)
    child Future<nil> = @async(helper(selected))
    @await(child)
}
start() {}
