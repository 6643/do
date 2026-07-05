#T
discard(seed T) -> i32 {
    _ = seed
    return 1
}

test "compiled generic storage param lower" {
    seed [u8] = "a"
    value i32 = discard(seed)
    if @eq(value, 1) return
}
