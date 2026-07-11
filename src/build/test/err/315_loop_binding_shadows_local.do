test "loop binding shadows local" {
    value i32 = 0
    xs [i32] = .{1}
    loop value, index = xs {
        consume(index)
    }
    return
}
