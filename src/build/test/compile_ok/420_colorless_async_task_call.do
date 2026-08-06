work() -> nil {
    return
}

resumable() -> i32 {
    pending Future<nil> = @async(work())
    @await(pending)
    return 7
}

run() -> i32 {
    pending Future<i32> = @async(resumable())
    result i32 = @await(pending)
    return result
}

start() {
    result i32 = run()
    _ = result
}
