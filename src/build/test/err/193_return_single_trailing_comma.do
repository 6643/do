value() -> i32 {
    return 1,
}

test "return single trailing comma" {
    x = value()
    return
}
