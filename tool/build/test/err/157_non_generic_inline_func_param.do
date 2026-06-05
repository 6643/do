apply(f (i32) -> i32) -> i32 {
    return f(1)
}

test "non generic inline func param" {
    x = apply((v i32) -> i32 => add(v, 1))
    return
}
