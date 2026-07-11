cleanup_a() -> nil {
    return
}

cleanup_b() -> nil {
    return
}

start() {
    defer cleanup_a()
    defer cleanup_b()
    return
}
