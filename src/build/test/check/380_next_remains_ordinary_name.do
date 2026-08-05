increment(next i32) -> i32 {
    return @add(next, 1)
}

start() {
    next i32 = 1
    output i32 = increment(next)
    _ = output
}
