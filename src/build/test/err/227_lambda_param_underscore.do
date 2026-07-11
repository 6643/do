#F = (i32) -> i32
apply(f F) -> i32 {
    return f(1)
}

test "lambda param underscore" {
    value = apply((_ i32) -> i32 => 1)
    consume(value)
}
