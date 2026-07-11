test "is extra type arg" {
    v i32 | bool = 1
    if @is(v, i32, bool) return
}
