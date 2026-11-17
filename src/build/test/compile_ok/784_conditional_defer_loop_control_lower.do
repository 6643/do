cleanup(value i32) -> nil {
    return
}

start() {
    enabled bool = true
    stop bool = false
    loop {
        defer(enabled) cleanup(1)
        enabled = false
        if stop break
        continue
    }
}
