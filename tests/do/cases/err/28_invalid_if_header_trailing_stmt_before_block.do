test "invalid if header trailing stmt before block" {
    a = 1
    b = 2
    if ge(a, b) and(ok_flag) {
        return
    }
}
