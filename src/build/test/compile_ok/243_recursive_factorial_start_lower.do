factorial(n i32) -> i32 {
    if @eq(n, 0) return 1
    next i32 = @sub(n, 1)
    return @mul(n, factorial(next))
}

start() {
    out i32 = factorial(5)
    if @eq(out, 120) return
    return
}
