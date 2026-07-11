sum_to(n i32) -> i32 {
    if @eq(n, 0) return 0
    next i32 = @sub(n, 1)
    return @add(n, sum_to(next))
}

is_even(n i32) -> bool {
    if @eq(n, 0) return true
    next i32 = @sub(n, 1)
    return is_odd(next)
}

is_odd(n i32) -> bool {
    if @eq(n, 0) return false
    next i32 = @sub(n, 1)
    return is_even(next)
}

start() {
    total i32 = sum_to(4)
    even bool = is_even(6)
    if @and(@eq(total, 10), even) return
    return
}
