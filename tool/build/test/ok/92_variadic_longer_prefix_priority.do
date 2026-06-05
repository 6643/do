ready(rest ...i32) -> i32 {
    return 0
}

ready(x i32, rest ...i32) -> bool {
    return true
}

test "longer variadic prefix wins" {
    if ready(1, 2) return
}
