one() -> i32 {
    return 1
}

test "multi lhs requires multi return call" {
    a, b = one()
    return
}
