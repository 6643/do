test "loop collection single binding" {
    xs [i32] = .{1}
    loop value = xs {
        consume(value)
    }
    return
}
