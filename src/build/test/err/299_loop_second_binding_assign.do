test "loop second binding assign" {
    xs [i32] = .{1}
    loop value, index = xs {
        index = 1
    }
    return
}
