test "lambda block return" {
    xs List<i32> = List<i32>{}
    result = map(xs, (x i32) -> i32 {
        y = add(x, 1)
        return y
    })
    return
}
