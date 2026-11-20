start() {
    xs [i32] = .{1}
    xs = @put(xs, 2, 3, 4)
    first i32 = @get(xs, 1)
    last i32 = @get(xs, 3)
    return
}
