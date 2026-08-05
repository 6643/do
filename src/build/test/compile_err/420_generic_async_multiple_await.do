work() -> nil { return }
run() -> nil {
    first Future<nil> = @async(work())
    @await(first)
    second Future<nil> = @async(work())
    @await(second)
    pending Future<nil> = @async(work())
    @cancel(pending)
}
start() {}
