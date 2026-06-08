start() {
    xs [i32] = .{1, 2}
    xs = @set(xs, 1, 9)
    xs = @put(xs, 10)
    value i32 = @get(xs, 2)
    return
}
