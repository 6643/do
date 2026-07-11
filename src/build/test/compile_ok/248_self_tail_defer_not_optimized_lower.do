cleanup() -> nil {
    return
}

sum_tail_with_defer(n i32, acc i32) -> i32 {
    defer cleanup()
    if @eq(n, 0) return acc
    next_n i32 = @sub(n, 1)
    next_acc i32 = @add(acc, n)
    return sum_tail_with_defer(next_n, next_acc)
}

start() {
    out i32 = sum_tail_with_defer(5, 0)
    return
}
