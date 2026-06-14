consume(bytes [u8]) -> nil {
    if @eq(@len(bytes), 3) return
}

test "compiled storage bare call last use move" {
    data [u8] = .{1, 2, 3}
    consume(data)
    return
}
