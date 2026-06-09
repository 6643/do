start() {
    xs [i32] = .{1, 2}
    loop value, index = xs {
        if @eq(index, 0) break
        value = value
    }
    return
}
