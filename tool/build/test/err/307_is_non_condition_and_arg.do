test "is non condition and arg" {
    value i32 | bool = 1
    ok bool = true
    ok = @and(ok, @is(value, i32))
    return
}
