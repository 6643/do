test "compiled guard return" {
    value i32 = @add(20, 22)
    if @eq(value, 42) return
}
