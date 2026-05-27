test "is value type guard" {
    v = to_i8(1234)
    if is(v, Error) return
}
