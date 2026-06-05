test "loop each discard index" {
    xs [i32] = .{}
    xs = put(xs, 1)
    xs = put(xs, 2)
    expected i32 = 1

    loop v, _ = xs {
        if eq(v, expected) return
    }
}
