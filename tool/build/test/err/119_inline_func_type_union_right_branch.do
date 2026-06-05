#T = i32 | () -> i32
use_callback(f T) {
    return
}

zero() -> i32 {
    return 0
}

test "inline func type union right branch" {
    use_callback(zero)
    return
}
