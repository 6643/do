pair() -> i32, i32 {
    return 1, 2
}

wrap() -> i32, i32 {
    return pair()
}

test "multi return passthrough" {
    a, b = wrap()
    return
}
