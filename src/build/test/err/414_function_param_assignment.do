set_value(value i32) -> i32 {
    value = 2
    return value
}

test "function parameter assignment" {
    value i32 = set_value(1)
    return
}
