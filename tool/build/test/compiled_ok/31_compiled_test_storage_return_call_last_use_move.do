make(x [u8]) -> [u8] {
    return x
}

pass(data [u8]) -> [u8] {
    return make(data)
}

test "compiled storage return call last use move" {
    data [u8] = .{1, 2, 3}
    out [u8] = pass(data)
    if @eq(out, .{1, 2, 3}) return
}
