DepthError error = Negative

sum_checked(n i32) -> i32 | DepthError {
    if @lt(n, 0) return Negative
    if @eq(n, 0) return 0
    next i32 = @sub(n, 1)
    partial = sum_checked(next)
    if @is(partial, DepthError) return partial
    return @add(n, partial)
}

test "recursive error union" {
    total = sum_checked(4)
    fail = sum_checked(-1)

    ok bool = true
    if @is(total, i32) {
        ok = @and(ok, @eq(total, 10))
    } else {
        ok = false
    }
    ok = @and(ok, @eq(fail, Negative))
    if ok return
}
