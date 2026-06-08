test "is type set nil branch" {
    v i32 | nil = 1
    if @is(v, i32 | nil) return
}
