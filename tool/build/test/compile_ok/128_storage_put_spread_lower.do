start() {
    xs [i32] = .{1}
    rest [i32] = .{2, 3}
    xs = @put(xs, ...rest)
    got i32 = @get(xs, 2)
    return
}
