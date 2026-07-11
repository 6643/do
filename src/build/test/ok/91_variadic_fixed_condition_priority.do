ready(rest ...i32) -> i32 {
    return 0
}

ready(x i32) -> bool {
    return true
}

test "fixed condition beats variadic" {
    if ready(1) return
}
