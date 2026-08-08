work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper(value u32) -> i32 {
    pending Future<nil> = work()
    @await(pending)
    return 1
}
run() -> nil {
    helper(7)
    child Future<i32> = @async(helper(7))
    @await(child)
}
start() {}
