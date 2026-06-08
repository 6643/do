#F = (i32) -> i32
apply(f F) -> i32 {
    return f(1)
}

#F = (i64) -> i64
apply(f F) -> i64 {
    return f(1)
}

test "local constraint name overload" {
    out = apply((x i32) -> i32 => @add(x, 1))
    return
}
