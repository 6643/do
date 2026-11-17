cleanup() -> i32 {
    return 1
}

start() {
    defer(true) cleanup()
}
