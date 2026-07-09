cleanup() -> nil {
    return
}

start() {
    defer cleanup()
    defer {
        tmp [u8] = "arc"
        cleanup()
    }
    return
}
