BytesError = @lib("bytes.do", BytesError)
BytesOutOfBounds = @lib("bytes.do", BytesOutOfBounds)
text_take = @lib("text.do", take)
text_take_or = @lib("text.do", take_or)
text_drop = @lib("text.do", drop)
text_drop_or = @lib("text.do", drop_or)

text_bytes_eq(value [u8] | BytesError, expect [u8]) -> bool {
    if @is(value, BytesError) return false
    return @eq(value, expect)
}

text_is_out_of_bounds(value [u8] | BytesError) -> bool {
    if @is(value, BytesError) return @eq(value, BytesOutOfBounds)
    return false
}

test "text take drop helpers" {
    head = text_take("abcdef", 3)
    bad_head = text_take("abc", 9)
    head_or, head_or_ok = text_take_or("abc", 9, "fallback")
    tail = text_drop("abcdef", 3)
    bad_tail = text_drop("abc", 9)
    tail_or, tail_or_ok = text_drop_or("abc", 9, "fallback")

    ok bool = true
    ok = @and(ok, text_bytes_eq(head, "abc"))
    ok = @and(ok, text_is_out_of_bounds(bad_head))
    ok = @and(ok, @not(head_or_ok))
    ok = @and(ok, @eq(head_or, "fallback"))
    ok = @and(ok, text_bytes_eq(tail, "def"))
    ok = @and(ok, text_is_out_of_bounds(bad_tail))
    ok = @and(ok, @not(tail_or_ok))
    ok = @and(ok, @eq(tail_or, "fallback"))
    if ok return
}
