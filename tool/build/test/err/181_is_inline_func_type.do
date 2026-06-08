zero() -> i32 {
    return 0
}

#F = () -> i32
accept(v F | i32) {
    if @is(v, () -> i32) return
    return
}

test "is inline func type" {
    accept(zero)
    return
}
