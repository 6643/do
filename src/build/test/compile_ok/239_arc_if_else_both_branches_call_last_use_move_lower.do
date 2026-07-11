consume(bytes [u8]) -> nil {
    if @eq(@len(bytes), 3) return
}

choose(data [u8], ok bool) -> nil {
    if ok {
        consume(data)
    } else {
        consume(data)
    }
    return
}

start() {
    input [u8] = "abc"
    choose(input, true)
    return
}
