start() {
    data [u8] = "abc"
    alias [u8] = data
    next [u8] = @set(data, 1, 90)
    size usize = @len(alias)
    _ = size
    return
}
