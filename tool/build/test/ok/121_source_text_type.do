text_bytes_of = @lib("text.do", bytes_of)
text_from = @lib("text.do", text_from)
text_byte_len = @lib("text.do", byte_len)
text_char_len = @lib("text.do", char_len)
Utf8Error = @lib("utf8.do", Utf8Error)

User {
    name text
}

echo(s text) -> text {
    return s
}

test "source text type" {
    name text = "amy"
    user User = User{name = name}
    got text = echo(@get(user, .name))
    raw [u8] = text_bytes_of(got)
    from_raw = text_from(raw)
    bad = text_from(.{255})
    ok bool = @eq(got, "amy")
    ok = @and(ok, @eq(raw, "amy"))
    ok = @and(ok, @eq(from_raw, "amy"))
    if @is(bad, Utf8Error) {
        ok = @and(ok, true)
    } else {
        ok = false
    }
    ok = @and(ok, @eq(text_byte_len("中"), 3))
    ok = @and(ok, @eq(text_char_len("中"), 1))
    if ok return
    return
}
