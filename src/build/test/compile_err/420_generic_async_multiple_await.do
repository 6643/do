work() -> nil { return }
run() -> nil {
    first Future<nil> = @async(work())
    @await(first)
    second Future<nil> = @async(work())
    @await(second)
    third Future<nil> = @async(work())
    @await(third)
    pending Future<nil> = @async(work())
    @cancel(pending)
}
start() {}
