test "is type arg nil" {
    v i32 | nil = 1
    if is(v, nil) return
    return
}
