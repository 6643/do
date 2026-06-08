inc(x i32) -> i32 {
    return @add(x, 1)
}

inc(x i64) -> i64 {
    return @add(x, 1)
}

test "function name value no target" {
    f = inc
    return
}
