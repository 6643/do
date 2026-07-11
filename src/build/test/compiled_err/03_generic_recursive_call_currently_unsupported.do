#T
generic_countdown(n i32, value T) -> T {
    if @eq(n, 0) return value
    next i32 = @sub(n, 1)
    return generic_countdown(next, value)
}

test "generic recursive call currently unsupported" {
    out i32 = generic_countdown(2, 9)
    if @eq(out, 9) return
}
