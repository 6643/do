ready_lit(x i32) -> bool {
    return true
}

ready_lit(x i64) -> bool {
    return true
}

test "if condition overload literal ambiguous" {
    if ready_lit(1) return
    return
}
