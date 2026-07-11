use_callback(f (() -> i32) | i32) {
    return
}

zero() -> i32 {
    return 0
}

test "inline func type union branch" {
    use_callback(zero)
    return
}
