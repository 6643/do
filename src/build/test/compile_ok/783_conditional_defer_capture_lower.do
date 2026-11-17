cleanup(value i32) -> nil {
    return
}

start() {
    enabled bool = true
    defer(enabled) cleanup(1)
    enabled = false
    return
}
