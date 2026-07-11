value() -> i32 {
    return 1
}

test "defer call requires nil" {
    defer value()
    return
}
