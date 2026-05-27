test "loop each index value" {
    xs List<i32> = List<i32>{}
    xs = put(xs, 1)
    xs = put(xs, 2)
    loop v, i = xs {
        if and(eq(i, 0), eq(v, 1)) return
    }
}
