bytes_drop = @bytes.do/drop
bytes_drop_or = @bytes.do/drop_or
bytes_first = @bytes.do/first
bytes_first_or = @bytes.do/first_or
bytes_last = @bytes.do/last
bytes_last_or = @bytes.do/last_or
bytes_replace = @bytes.do/replace
bytes_slice_or = @bytes.do/slice_or
bytes_take = @bytes.do/take
bytes_take_or = @bytes.do/take_or

text_concat = @text.do/concat
text_copy = @text.do/copy
text_drop = @text.do/drop
text_first = @text.do/first
text_first_or = @text.do/first_or
text_index_of = @text.do/index_of
text_last = @text.do/last
text_last_or = @text.do/last_or
text_last_index_of = @text.do/last_index_of
text_replace = @text.do/replace
text_repeat_byte = @text.do/repeat_byte
text_slice_or = @text.do/slice_or
text_take = @text.do/take
text_trim_left_byte = @text.do/trim_left_byte
text_trim_byte = @text.do/trim_byte
text_trim_right_byte = @text.do/trim_right_byte

test "bytes common wrappers" {
    fallback [u8] = "fallback"
    part, part_ok = bytes_slice_or("abcdef", 1, 4, fallback)
    bad, bad_ok = bytes_slice_or("abcdef", 5, 2, fallback)
    head = bytes_take("abcdef", 2)
    tail = bytes_drop("abcdef", 2)
    head_or, head_or_ok = bytes_take_or("abc", 9, fallback)
    tail_or, tail_or_ok = bytes_drop_or("abc", 9, fallback)
    first_value, first_ok = bytes_first_or("abc", 0)
    missing_first, missing_first_ok = bytes_first_or("", 9)
    last_value, last_ok = bytes_last_or("abc", 0)
    missing_last, missing_last_ok = bytes_last_or("", 9)
    replaced [u8] = bytes_replace("one two two", "two", "2")
    unchanged [u8] = bytes_replace("abc", "", "x")

    ok bool = true
    ok = and(ok, part_ok)
    ok = and(ok, eq(part, "bcd"))
    ok = and(ok, not(bad_ok))
    ok = and(ok, eq(bad, fallback))
    ok = and(ok, eq(head, "ab"))
    ok = and(ok, eq(tail, "cdef"))
    ok = and(ok, not(head_or_ok))
    ok = and(ok, eq(head_or, fallback))
    ok = and(ok, not(tail_or_ok))
    ok = and(ok, eq(tail_or, fallback))
    ok = and(ok, eq(bytes_first("abc"), 97))
    ok = and(ok, first_ok)
    ok = and(ok, eq(first_value, 97))
    ok = and(ok, not(missing_first_ok))
    ok = and(ok, eq(missing_first, 9))
    ok = and(ok, eq(bytes_last("abc"), 99))
    ok = and(ok, last_ok)
    ok = and(ok, eq(last_value, 99))
    ok = and(ok, not(missing_last_ok))
    ok = and(ok, eq(missing_last, 9))
    ok = and(ok, eq(replaced, "one 2 2"))
    ok = and(ok, eq(unchanged, "abc"))
    if ok return
}

test "text common wrappers" {
    fallback [u8] = "fallback"
    part, part_ok = text_slice_or("abcdef", 2, 5, fallback)
    head = text_take("abcdef", 3)
    tail = text_drop("abcdef", 3)
    copied [u8] = text_copy("abc")
    cat [u8] = text_concat("ab", "cd", "ef")
    repeated [u8] = text_repeat_byte(120, 3)
    left_trimmed [u8] = text_trim_left_byte("  hello  ", 32)
    trimmed [u8] = text_trim_byte("  hello  ", 32)
    right_trimmed [u8] = text_trim_right_byte("  hello  ", 32)
    first_value, first_ok = text_first_or("abc", 0)
    missing_first, missing_first_ok = text_first_or("", 9)
    last_value, last_ok = text_last_or("abc", 0)
    missing_last, missing_last_ok = text_last_or("", 9)
    replaced [u8] = text_replace("a-b-c", "-", "/")

    ok bool = true
    ok = and(ok, part_ok)
    ok = and(ok, eq(part, "cde"))
    ok = and(ok, eq(head, "abc"))
    ok = and(ok, eq(tail, "def"))
    ok = and(ok, eq(copied, "abc"))
    ok = and(ok, eq(cat, "abcdef"))
    ok = and(ok, eq(repeated, "xxx"))
    ok = and(ok, eq(left_trimmed, "hello  "))
    ok = and(ok, eq(trimmed, "hello"))
    ok = and(ok, eq(right_trimmed, "  hello"))
    ok = and(ok, eq(text_first("abc"), 97))
    ok = and(ok, first_ok)
    ok = and(ok, eq(first_value, 97))
    ok = and(ok, not(missing_first_ok))
    ok = and(ok, eq(missing_first, 9))
    ok = and(ok, eq(text_last("abc"), 99))
    ok = and(ok, last_ok)
    ok = and(ok, eq(last_value, 99))
    ok = and(ok, not(missing_last_ok))
    ok = and(ok, eq(missing_last, 9))
    ok = and(ok, eq(replaced, "a/b/c"))
    ok = and(ok, eq(text_index_of("abcabc", "bc"), 1))
    ok = and(ok, eq(text_last_index_of("abcabc", "bc"), 4))
    if ok return
}
