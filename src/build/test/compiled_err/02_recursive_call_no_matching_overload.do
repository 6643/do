bad(n i32) -> i32 {
    return bad(true)
}

test "recursive call no matching overload" {
    bad(1)
    return
}
