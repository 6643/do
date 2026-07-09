factorial(n i32) -> i32 {
    if @eq(n, 0) return 1
    next i32 = @sub(n, 1)
    return @mul(n, factorial(next))
}

choose_sum(n i32, include bool) -> i32 {
    if @eq(n, 0) return 0
    next i32 = @sub(n, 1)
    if include {
        return @add(n, choose_sum(next, include))
    } else {
        return choose_sum(next, include)
    }
}
