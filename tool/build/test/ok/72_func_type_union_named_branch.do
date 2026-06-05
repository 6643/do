#F = () -> i32
use_callback(f F) {
    _ = f()
    return
}

zero() -> i32 {
    return 0
}

test "func type union named branch" {
    use_callback(zero)
    return
}
