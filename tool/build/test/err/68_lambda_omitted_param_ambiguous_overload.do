#F32 = (i32) -> i32
apply(f F32) -> i32 {
    return f(1)
}

#F64 = (i64) -> i64
apply(f F64) -> i64 {
    return f(1)
}

test "lambda omitted param ambiguous overload" {
    v = apply((x) => add(x, 1))
    return
}
