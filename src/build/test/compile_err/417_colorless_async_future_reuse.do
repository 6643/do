work() -> nil {
    return
}

run() -> nil {
    pending Future<nil> = @async(work())
    @await(pending)
    @await(pending)
}

start() {}
