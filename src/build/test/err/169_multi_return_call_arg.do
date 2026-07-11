pair() -> i32, i32 {
    return 1, 2
}

sink(x i32) {
    return
}

test "multi return call arg" {
    sink(pair())
    return
}
