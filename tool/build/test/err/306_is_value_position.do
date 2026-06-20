test "is value position" {
    value i32 | bool = 1
    ok bool = @is(value, i32)
    return
}
