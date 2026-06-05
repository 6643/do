bad() -> i32, i32 {
    return 1
}

test "multi return passthrough requires call" {
    a, b = bad()
    return
}
