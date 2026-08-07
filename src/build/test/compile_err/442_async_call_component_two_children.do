work = @host("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
helper() -> nil {
    pending Future<nil> = work()
    @await(pending)
}
run() -> nil {
    first Future<nil> = @async(helper())
    second Future<nil> = @async(helper())
    @await(first)
    @await(second)
}
start() {}
