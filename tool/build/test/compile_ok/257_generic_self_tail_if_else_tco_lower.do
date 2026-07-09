#T
choose_tail(n i32, value T, keep bool) -> T {
    if @eq(n, 0) return value
    next_n i32 = @sub(n, 1)
    if keep {
        return choose_tail(next_n, value, false)
    } else {
        return choose_tail(next_n, value, true)
    }
}

start() {
    seed i32 = 7
    out i32 = choose_tail(4, seed, true)
    return
}
