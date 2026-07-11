choose_sum(n i32, include bool) -> i32 {
    if @eq(n, 0) return 0
    next i32 = @sub(n, 1)
    if include {
        return @add(n, choose_sum(next, include))
    } else {
        return choose_sum(next, include)
    }
}

test "compiled recursive if else" {
    out i32 = choose_sum(4, true)
    if @eq(out, 10) return
}
