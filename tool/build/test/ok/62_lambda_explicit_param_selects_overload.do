#F32 = (i32) -> i32
apply(f F32) -> i32 {
    return f(1)
}

#F64 = (i64) -> i64
apply(f F64) -> i64 {
    return f(1)
}

test "lambda explicit param selects overload" {
    v = apply((x i32) => @add(x, 1))
    return
}
