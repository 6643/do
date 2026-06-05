count() -> i32 {
    return 1
}

test "if condition non bool call" {
    if count() return
    return
}
