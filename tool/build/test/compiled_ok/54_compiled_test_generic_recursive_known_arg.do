#T
generic_countdown(n i32, value T) -> T {
    if @eq(n, 0) return value
    next i32 = @sub(n, 1)
    return generic_countdown(next, value)
}

test "compiled generic recursive known arg" {
    seed i32 = 9
    out i32 = generic_countdown(2, seed)
    if @eq(out, 9) return
}
