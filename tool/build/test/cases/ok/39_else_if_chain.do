f(a bool, b bool) -> i32 {
    if a {
        return 1
    } else if b {
        return 2
    } else {
        return 3
    }
}

test "else if chain" {
    expected i32 = 2
    if eq(f(false, true), expected) return
}
