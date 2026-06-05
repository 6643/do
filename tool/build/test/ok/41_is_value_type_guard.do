test "is value type guard" {
    v i32 | bool = false
    if is(v, bool) return
}
