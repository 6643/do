update(data [u8]) -> usize {
    data = "def"
    return @len(data)
}

start() {
    source [u8] = "abc"
    n usize = update(source)
    return
}
