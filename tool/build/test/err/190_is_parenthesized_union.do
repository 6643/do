test "is parenthesized union" {
    v i32 | i64 = 1
    if is(v, (i32 | i64)) return
    return
}
