update(x i32) -> i32 {
    x = @add(x, 1)
    return x
}

start() {
    _ = update(1)
    return
}
