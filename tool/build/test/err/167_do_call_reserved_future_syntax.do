pair() -> i32, bool {
    return 1, true
}

bad() -> i32, bool {
    return do pair()
}

test "do call is reserved future syntax" {
    x, ok = bad()
    return
}
