consume(bytes [u8]) -> nil {
    if @eq(@len(bytes), 3) return
}

start() {
    data [u8] = "abc"
    consume(data)
    return
}
