test "is parenthesized type" {
    v i32 | i64 = 1
    if @is(v, (i32)) return
    return
}
