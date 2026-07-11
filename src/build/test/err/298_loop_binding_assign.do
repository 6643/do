test "loop binding assign" {
    xs [i32] = .{1}
    loop value, index = xs {
        value = value
    }
    return
}
