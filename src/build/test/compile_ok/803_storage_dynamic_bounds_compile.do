start() {
    data [u8] = .{1}
    got u8 = @get(data, 1)
    next [u8] = @set(data, 1, 2)
    return
}
