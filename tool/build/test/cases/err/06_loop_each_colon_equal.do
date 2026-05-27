test "loop each colon equal" {
    xs List<i32> = List<i32>{}
    xs = put(xs, 1)
    xs = put(xs, 2)

    loop v, i := xs {
        return
    }
}
