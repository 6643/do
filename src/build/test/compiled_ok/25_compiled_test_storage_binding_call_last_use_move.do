make(x [u8]) -> [u8] {
    return x
}

test "compiled storage binding call last use move" {
    data [u8] = .{1, 2, 3}
    out [u8] = make(data)
    if @eq(out, .{1, 2, 3}) return
}
