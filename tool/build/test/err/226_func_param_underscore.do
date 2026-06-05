ignore(_ i32) -> i32 {
    return 0
}

test "func param underscore" {
    value = ignore(1)
    consume(value)
}
