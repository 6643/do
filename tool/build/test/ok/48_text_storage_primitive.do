Text = @/text.do/Text

test "text storage primitive" {
    s Text = "abc"
    if eq(len(s), 3) return
}
