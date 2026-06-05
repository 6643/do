ready_value(x i32) -> bool {
    return true
}

ready_value(x i64) -> i64 {
    return x
}

test "if condition overload typed arg" {
    x i32 = 1
    if ready_value(x) return
    return
}
