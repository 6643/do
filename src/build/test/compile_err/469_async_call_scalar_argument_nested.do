work = @host("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
inner() -> nil {}
helper(value u32) -> nil {
    inner()
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    child Future<nil> = @async(helper(7))
    @await(child)
}
start() {}
