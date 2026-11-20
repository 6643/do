increment(x i32) -> i32 {
    return @add(x, 1)
}

start() {
    _ = increment(1)
    return
}
