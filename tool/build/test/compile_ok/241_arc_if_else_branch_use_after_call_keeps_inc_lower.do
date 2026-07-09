take(bytes [u8]) -> usize {
    return @len(bytes)
}

choose(data [u8], ok bool) -> usize {
    total usize = 0
    if ok {
        first usize = take(data)
        second usize = @len(data)
        total = @add(first, second)
    } else {
        total = take(data)
    }
    return total
}

start() {
    input [u8] = "abc"
    size usize = choose(input, true)
    return
}
