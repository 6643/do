add(a i32, b i32) i32 => a

test "call multiline trailing comma" {
    x = add(
        1,
        2,
    )
    expected i32 = 1
    if eq(x, expected) return
}
