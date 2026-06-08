inc(x i32) -> i32 {
    return @add(x, 1)
}

inc(x i64) -> i64 {
    return @add(x, 1)
}

#F = (i32) -> i32
apply(f F) -> i32 {
    return f(1)
}

test "function name selects overload" {
    v = apply(inc)
    return
}
