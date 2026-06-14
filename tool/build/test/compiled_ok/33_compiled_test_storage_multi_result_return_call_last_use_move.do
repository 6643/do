pair_take(x [u8]) -> [u8], i32 {
    return x, 3
}

pass(data [u8]) -> [u8], i32 {
    return pair_take(data)
}

test "compiled storage multi-result return call last use move" {
    data [u8] = .{1, 2, 3}
    out [u8] = .{}
    n i32 = 0
    out, n = pass(data)
    if @and(@eq(out, .{1, 2, 3}), @eq(n, 3)) return
}
