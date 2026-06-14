take(x [u8]) -> i32 {
    return @len(x)
}

test "compiled storage inferred call last use move" {
    data [u8] = .{1, 2, 3}
    n = take(data)
    if @eq(n, 3) return
}
