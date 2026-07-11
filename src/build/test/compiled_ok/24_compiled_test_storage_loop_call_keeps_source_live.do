take(x [u8]) -> i32 {
    return @len(x)
}

test "compiled storage loop call keeps source live" {
    data [u8] = .{1, 2, 3}
    first i32 = 0
    second i32 = 0
    loop {
        first = take(data)
        second = take(data)
        if @eq(second, 3) return
        break
    }
}
