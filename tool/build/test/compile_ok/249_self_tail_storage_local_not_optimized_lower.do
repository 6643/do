sum_tail_with_storage(n i32, acc i32) -> i32 {
    note [u8] = "a"
    if @eq(n, 0) return acc
    next_n i32 = @sub(n, 1)
    next_acc i32 = @add(acc, @len(note))
    return sum_tail_with_storage(next_n, next_acc)
}

start() {
    out i32 = sum_tail_with_storage(5, 0)
    return
}
