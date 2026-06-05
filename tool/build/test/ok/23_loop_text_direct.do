
test "loop text direct" {
    s [u8] = "abc"
    loop v, i = s {
        if eq(i, 0) return
        consume(v)
    }
}
