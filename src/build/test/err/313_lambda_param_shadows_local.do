#F = (i32) -> i32
apply(value i32, f F) -> i32 {
    return f(value)
}

test "lambda param shadows local" {
    x i32 = 1
    value = apply(2, (x i32) -> i32 => x)
    consume(value)
}
