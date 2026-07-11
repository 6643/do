text_slice_or = @lib("text.do", slice_or)

test "text slice helpers" {
    fallback [u8] = "fallback"
    part, part_ok = text_slice_or("abcdef", 2, 5, fallback)
    bad, bad_ok = text_slice_or("abcdef", 5, 2, fallback)

    ok bool = true
    ok = @and(ok, part_ok)
    ok = @and(ok, @eq(part, "cde"))
    ok = @and(ok, @not(bad_ok))
    ok = @and(ok, @eq(bad, fallback))
    if ok return
}
