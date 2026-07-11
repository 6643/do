cleanup() -> nil {
    return
}

start() {
    loop {
        data [u8] = "data"
        defer cleanup()
        continue
    }
}
