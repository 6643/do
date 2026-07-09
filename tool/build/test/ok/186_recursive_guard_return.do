sum_positive(n i32) -> i32 {
    if @lt(n, 0) return 0
    if @eq(n, 0) return 0
    next i32 = @sub(n, 1)
    return @add(n, sum_positive(next))
}

test "recursive guard return" {
    out i32 = sum_positive(4)
    if @eq(out, 10) return
}
