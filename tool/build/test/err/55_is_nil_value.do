test "is nil value" {
    v i32 | nil = nil
    if @is(v, nil) return
}
