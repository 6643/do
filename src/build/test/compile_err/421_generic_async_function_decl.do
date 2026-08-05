work() -> nil { return }
async run() -> nil {
    ready Future<nil> = @async(work())
    @await(ready)
    pending Future<nil> = @async(work())
    @cancel(pending)
}
start() {}
