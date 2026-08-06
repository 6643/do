ready() -> i32 {
    return 1
}

run() -> nil {
    pending Future<i32> = @async(ready())
    value i32 = @await(pending)
    _ = value
}

start() {
    run()
}
