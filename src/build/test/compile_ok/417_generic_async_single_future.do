work() -> nil { return }
run() -> nil {
    ready Future<nil> = @async(work())
    @await(ready)
    pending Future<nil> = @async(work())
    @cancel(pending)
}
start() { run() }
