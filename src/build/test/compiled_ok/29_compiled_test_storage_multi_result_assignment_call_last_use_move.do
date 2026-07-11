pair_take(x [u8]) -> [u8], i32 {
    return x, 3
}

test "compiled storage multi-result assignment call last use move" {
    data [u8] = .{1, 2, 3}
    out [u8] = .{}
    n i32 = 0
    out, n = pair_take(data)
    if @and(@eq(out, .{1, 2, 3}), @eq(n, 3)) return
}
