Text = @/text.do/Text

test "loop text direct" {
    s Text = "abc"
    loop v, i = s {
        if eq(i, 0) return
        consume(v)
    }
}
