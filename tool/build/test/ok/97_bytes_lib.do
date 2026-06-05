bytes_concat = @bytes.do/concat
bytes_contains = @bytes.do/contains
bytes_ends_with = @bytes.do/ends_with
BytesError = @bytes.do/BytesError
BytesInvalidRange = @bytes.do/BytesInvalidRange
bytes_index_of = @bytes.do/index_of
bytes_last_index_of = @bytes.do/last_index_of
bytes_repeat_byte = @bytes.do/repeat_byte
bytes_slice = @bytes.do/slice
bytes_starts_with = @bytes.do/starts_with
bytes_trim_byte = @bytes.do/trim_byte

test "bytes sequence ops" {
    text [u8] = "  abc abc  "
    cat [u8] = bytes_concat("ab", "cd", "ef")
    repeated [u8] = bytes_repeat_byte(120, 3)
    mid = bytes_slice(text, 2, 9)
    trimmed [u8] = bytes_trim_byte(text, 32)

    ok bool = true
    ok = and(ok, eq(cat, "abcdef"))
    ok = and(ok, eq(repeated, "xxx"))
    ok = and(ok, eq(mid, "abc abc"))
    ok = and(ok, eq(trimmed, "abc abc"))
    ok = and(ok, bytes_starts_with(text, "  a"))
    ok = and(ok, bytes_ends_with(text, "  "))
    ok = and(ok, bytes_contains(text, "bc a"))
    ok = and(ok, eq(bytes_index_of(text, "abc"), 2))
    ok = and(ok, eq(bytes_last_index_of(text, "abc"), 6))
    if ok return
}

test "bytes invalid slice" {
    bad = bytes_slice("abc", 3, 2)
    if eq(bad, BytesInvalidRange) return
}
