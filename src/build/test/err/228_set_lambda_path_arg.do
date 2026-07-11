test "set lambda path arg" {
    xs [i32] = .{1, 2}
    xs = @set(xs, (x i32) => x, 9)
    return
}
