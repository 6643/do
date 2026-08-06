work() -> nil {
    return
}

run() -> nil {
    pending Future<nil> = @async(work())
}

start() {}
