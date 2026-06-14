take(x [u8]) -> i32 {
    return @len(x)
}

test "compiled storage scalar call last use move" {
    data [u8] = .{1, 2, 3}
    n i32 = take(data)
    if @eq(n, 3) return
}
