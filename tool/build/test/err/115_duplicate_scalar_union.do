same(x i32) -> i32 | i32 {
    return x
}

test "duplicate scalar union" {
    v = same(1)
    if is(v, i32) return
}
