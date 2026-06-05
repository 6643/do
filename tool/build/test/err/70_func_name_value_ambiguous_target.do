inc(x i32) -> i32 {
    return add(x, 1)
}

inc(x i64) -> i64 {
    return add(x, 1)
}

#F32 = (i32) -> i32
use(f F32) -> i32 {
    return f(1)
}

#F64 = (i64) -> i64
use(f F64) -> i64 {
    return f(1)
}

test "function name value ambiguous target" {
    v = use(inc)
    return
}
