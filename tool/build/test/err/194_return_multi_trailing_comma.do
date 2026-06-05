pair() -> i32, i32 {
    return 1, 2,
}

test "return multi trailing comma" {
    a, b = pair()
    return
}
