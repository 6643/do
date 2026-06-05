pair = @./fixture.import_multi_return.do/pair

forward(x i32) -> i32, bool {
    return pair(x)
}

test "imported multi return values" {
    n, ok = pair(1)
    out_n, out_ok = forward(n)
    pass_n, pass_ok = pair(out_n)
    return
}
