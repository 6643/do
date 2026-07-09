take(xs [i32]) -> i32 {
    return @len(xs)
}

start() {
    xs [i32] = .{1, 2}
    loop value, index = xs {
        n i32 = take(xs)
        if @eq(index, 0) break
    }
    return
}
