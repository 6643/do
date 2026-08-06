work() -> nil { return }
run() -> nil {
    ready Future<nil> = @async(work())
    @await(ready)
    middle Future<nil> = @async(work())
    @await(middle)
    pending Future<nil> = @async(work())
    @cancel(pending)
}
start() { run() }
