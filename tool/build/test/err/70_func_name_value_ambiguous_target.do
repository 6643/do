inc(x i32) -> i32 {
    return add(x, 1)
}

inc(x i64) -> i64 {
    return add(x, 1)
}

use(f (i32) -> i32) -> i32 {
    return f(1)
}

use(f (i64) -> i64) -> i64 {
    return f(1)
}

test "function name value ambiguous target" {
    v = use(inc)
    return
}
