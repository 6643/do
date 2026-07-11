pair = @lib("./fixture.import_multi_return.do", pair)

sink(x i32) {
    return
}

test "imported multi return call arg" {
    sink(pair(1))
    return
}
