work = @host("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
inner() -> nil {}
helper() -> nil {
    inner()
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    child Future<nil> = @async(helper())
    @await(child)
}
start() {}
