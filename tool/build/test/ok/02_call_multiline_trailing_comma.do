test "call multiline trailing comma" {
    x = @add(1, 2)
    expected i32 = 3
    if @eq(x, expected) return
}
