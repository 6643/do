id(input [u8]) -> [u8] {
    return input
}

choose(source [u8], ok bool) -> [u8] {
    if ok return id(source)
    n usize = @len(source)
    return source
}

start() {
    data [u8] = "abc"
    out [u8] = choose(data, true)
    return
}
