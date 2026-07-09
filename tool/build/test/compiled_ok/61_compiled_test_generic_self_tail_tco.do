#T
last_tail(n i32, value T) -> T {
    if @eq(n, 0) return value
    next i32 = @sub(n, 1)
    return last_tail(next, value)
}

test "compiled generic self tail tco" {
    seed i32 = 7
    out i32 = last_tail(4, seed)
    if @eq(out, 7) return
}
