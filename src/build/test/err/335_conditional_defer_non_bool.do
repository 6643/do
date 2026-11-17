cleanup() -> nil {
    return
}

start() {
    value i32 = 1
    defer(value) cleanup()
}
