step_pair(n i32, acc i32) -> i32, i32 {
    if @eq(n, 0) return n, acc
    next i32 = @sub(n, 1)
    next_acc i32 = @add(acc, n)
    return step_pair(next, next_acc)
}

start() {
    left i32 = 0
    right i32 = 0
    left, right = step_pair(4, 0)
    return
}
