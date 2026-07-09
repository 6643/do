sum_guard(n i32, acc i32, flip bool) -> i32 {
    if @eq(n, 0) return acc
    next_n i32 = @sub(n, 1)
    next_acc i32 = @add(acc, n)
    if flip return sum_guard(next_n, next_acc, false)
    return sum_guard(next_n, acc, true)
}

test "compiled self tail guard tco" {
    out i32 = sum_guard(5, 0, true)
    if @eq(out, 9) return
}
