count(rest ...i32) -> i32 {
    return 0
}

test "variadic rest allows zero args" {
    x = count()
    if eq(x, 0) return
}
