pair = @./fixture.import_multi_return.do/pair

test "imported multi return single bind" {
    x = pair(1)
    return
}
