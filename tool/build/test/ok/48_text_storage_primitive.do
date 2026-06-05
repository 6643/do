
test "text storage primitive" {
    s [u8] = "abc"
    if eq(len(s), 3) return
}
