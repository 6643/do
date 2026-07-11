dup(x i32, x i32) -> i32 {
    return x
}

test "duplicate func param" {
    value = dup(1, 2)
    consume(value)
}
