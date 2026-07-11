sum_branch(n i32, acc i32, include bool) -> i32 {
    if @eq(n, 0) return acc
    next_n i32 = @sub(n, 1)
    if include {
        next_acc i32 = @add(acc, n)
        return sum_branch(next_n, next_acc, include)
    } else {
        return sum_branch(next_n, acc, include)
    }
}

start() {
    out i32 = sum_branch(5, 0, true)
    return
}
