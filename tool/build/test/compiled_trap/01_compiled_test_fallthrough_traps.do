test "compiled fallthrough traps" {
    value i32 = 1
    if @eq(value, 2) return
}
