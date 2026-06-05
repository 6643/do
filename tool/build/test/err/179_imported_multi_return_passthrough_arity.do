pair = @./fixture.import_multi_return.do/pair

bad(x i32) -> i32, bool, i32 {
    return pair(x)
}

test "imported multi return passthrough arity" {
    a, b, c = bad(1)
    return
}
