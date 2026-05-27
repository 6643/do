test "lambda local capture" {
    step i32 = 1
    result = map(xs, (x i32) => add(x, step))
    return
}
