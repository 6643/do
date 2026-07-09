consume(bytes [u8]) -> nil {
    if @eq(@len(bytes), 3) return
}

choose(data [u8], ok bool) -> usize {
    if ok {
        consume(data)
        return 0
    } else {
        size usize = @len(data)
        return size
    }
}

start() {
    input [u8] = "abc"
    size usize = choose(input, true)
    return
}
