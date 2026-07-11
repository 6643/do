test "duplicate loop binding" {
    xs [i32] = .{1}
    loop value, value = xs {
        consume(value)
    }
    return
}
