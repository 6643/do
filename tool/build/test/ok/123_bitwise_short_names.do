test "bitwise short names" {
    a u32 = @and(7, 3)
    b u32 = @or(8, 1)
    c u32 = @xor(6, 3)
    ok bool = @and(@eq(a, 3), @eq(b, 9), @eq(c, 5))
    if ok return
}
