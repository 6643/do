test "is union type set" {
    v i32 | i64 | bool = 1
    if is(v, i32 | i64) return
}
