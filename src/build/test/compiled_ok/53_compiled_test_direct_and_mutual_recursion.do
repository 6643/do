countdown(n i32) -> i32 {
    if @eq(n, 0) return 0
    next i32 = @sub(n, 1)
    return countdown(next)
}

is_even(n i32) -> bool {
    if @eq(n, 0) return true
    next i32 = @sub(n, 1)
    return is_odd(next)
}

is_odd(n i32) -> bool {
    if @eq(n, 0) return false
    next i32 = @sub(n, 1)
    return is_even(next)
}

test "compiled direct and mutual recursion" {
    direct i32 = countdown(3)
    even bool = is_even(4)
    odd bool = is_odd(5)

    ok bool = true
    ok = @and(ok, @eq(direct, 0))
    ok = @and(ok, even)
    ok = @and(ok, odd)
    if ok return
}
