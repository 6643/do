cleanup() -> nil {
    return
}

sum_guard_with_defer(n i32, acc i32, flip bool) -> i32 {
    defer cleanup()
    if @eq(n, 0) return acc
    next_n i32 = @sub(n, 1)
    next_acc i32 = @add(acc, n)
    if flip return sum_guard_with_defer(next_n, next_acc, false)
    return sum_guard_with_defer(next_n, acc, true)
}

start() {
    out i32 = sum_guard_with_defer(5, 0, true)
    return
}
