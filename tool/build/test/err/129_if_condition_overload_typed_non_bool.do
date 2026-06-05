flag_value(x i32) -> i32 {
    return x
}

flag_value(x i64) -> bool {
    return true
}

test "if condition overload typed non bool" {
    x i32 = 1
    if flag_value(x) return
    return
}
