work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper() -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    helper()
    helper()
    child Future<nil> = @async(helper())
    @await(child)
}
start() {}
