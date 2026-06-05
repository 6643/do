one = @./fixture.import_multi_return.do/one

test "imported multi lhs requires multi return call" {
    x, ok = one(1)
    return
}
