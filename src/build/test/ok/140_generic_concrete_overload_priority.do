pick(x i32) -> i32 {
    return @add(x, 1)
}

#T
pick(x T) -> T {
    return x
}

compiled_only_marker() -> nil {
    return
}

test "generic concrete overload priority" {
    defer compiled_only_marker()

    i i32 = 1
    b bool = true
    got_i = pick(i)
    got_b = pick(b)
    if @and(@eq(got_i, 2), got_b) return
}
