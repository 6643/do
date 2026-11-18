cleanup_a() -> nil {
    return
}

cleanup_b() -> nil {
    return
}

start() {
    defer(true) cleanup_a()
    defer(false) cleanup_b()
    if true {
        defer(true) {
            cleanup_a()
        }
    }
    return
}
