cleanup() -> nil {
    return
}

sum_branch_with_defer(n i32, acc i32, include bool) -> i32 {
    defer cleanup()
    if @eq(n, 0) return acc
    next_n i32 = @sub(n, 1)
    if include {
        next_acc i32 = @add(acc, n)
        return sum_branch_with_defer(next_n, next_acc, false)
    } else {
        return sum_branch_with_defer(next_n, acc, true)
    }
}

start() {
    out i32 = sum_branch_with_defer(5, 0, true)
    return
}
