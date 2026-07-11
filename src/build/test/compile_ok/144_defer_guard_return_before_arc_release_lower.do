cleanup() -> nil {
    return
}

start() {
    data [u8] = "data"
    defer cleanup()
    if @eq(@len(data), 4) return
    return
}
