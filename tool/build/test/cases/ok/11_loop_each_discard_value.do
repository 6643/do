test "loop each discard value" {
    xs List<i32> = List<i32>{}
    xs = put(xs, 1)
    xs = put(xs, 2)

    loop _, i = xs {
        if eq(i, 0) return
    }
}
