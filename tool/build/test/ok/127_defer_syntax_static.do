cleanup() -> nil {
    return
}

test "defer call and block syntax" {
    defer cleanup()
    defer {
        cleanup()
    }
    return
}
