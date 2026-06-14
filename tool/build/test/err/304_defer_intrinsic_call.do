test "defer intrinsic call" {
    defer @add(1, 2)
    return
}
