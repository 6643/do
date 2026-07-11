start() {
    data [u8] = "abc"
    next [u8] = @set(data, 1, 90)
    next = @put(next, 33)
    return
}
