work() -> nil {
    return
}

run() -> nil {
    pending Future<nil> = work()
    @await(pending)
}

start() {}
