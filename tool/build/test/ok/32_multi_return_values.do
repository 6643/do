pair() -> i32, i32 {
    return 1, 2
}

test "multi return values" {
    a, b = pair()
    return
}
