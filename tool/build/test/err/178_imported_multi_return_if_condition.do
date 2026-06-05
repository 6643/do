pair = @./fixture.import_multi_return.do/pair

test "imported multi return if condition" {
    if pair(1) return
    return
}
