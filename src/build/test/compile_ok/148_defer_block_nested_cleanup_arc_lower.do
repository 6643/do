cleanup() -> nil {
    return
}

start() {
    defer {
        tmp [u8] = "tmp"
        defer cleanup()
    }
    return
}
