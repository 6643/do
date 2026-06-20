#F = (i32, i32) -> i32
apply(a i32, b i32, f F) -> i32 {
    return f(a, b)
}

test "duplicate lambda param" {
    value = apply(1, 2, (x i32, x i32) -> i32 => x)
    consume(value)
}
