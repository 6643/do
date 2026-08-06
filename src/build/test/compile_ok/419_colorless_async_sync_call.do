work() -> nil {
    return
}

resumable() -> i32 {
    pending Future<nil> = @async(work())
    @await(pending)
    return 7
}

run() -> i32 {
    return resumable()
}

start() {
    result i32 = run()
    _ = result
}
