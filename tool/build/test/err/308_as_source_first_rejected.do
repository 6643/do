test "as source first rejected" {
    value i32 = 1
    converted i32 = @as(value, i32)
    return
}
