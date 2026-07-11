sum_tail(n i32, acc i32) -> i32 {
    if @eq(n, 0) return acc
    next_n i32 = @sub(n, 1)
    next_acc i32 = @add(acc, n)
    return sum_tail(next_n, next_acc)
}
