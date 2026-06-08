bytes_concat = @lib("bytes.do", concat)
bytes_contains = @lib("bytes.do", contains)
bytes_ends_with = @lib("bytes.do", ends_with)
BytesError = @lib("bytes.do", BytesError)
BytesInvalidRange = @lib("bytes.do", BytesInvalidRange)
bytes_index_of = @lib("bytes.do", index_of)
bytes_last_index_of = @lib("bytes.do", last_index_of)
bytes_repeat_byte = @lib("bytes.do", repeat_byte)
bytes_slice = @lib("bytes.do", slice)
bytes_starts_with = @lib("bytes.do", starts_with)
bytes_trim_byte = @lib("bytes.do", trim_byte)

test "bytes sequence ops" {
    bytes [u8] = "  abc abc  "
    cat [u8] = bytes_concat("ab", "cd", "ef")
    repeated [u8] = bytes_repeat_byte(120, 3)
    mid = bytes_slice(bytes, 2, 9)
    trimmed [u8] = bytes_trim_byte(bytes, 32)

    ok bool = true
    ok = @and(ok, @eq(cat, "abcdef"))
    ok = @and(ok, @eq(repeated, "xxx"))
    ok = @and(ok, @eq(mid, "abc abc"))
    ok = @and(ok, @eq(trimmed, "abc abc"))
    ok = @and(ok, bytes_starts_with(bytes, "  a"))
    ok = @and(ok, bytes_ends_with(bytes, "  "))
    ok = @and(ok, bytes_contains(bytes, "bc a"))
    ok = @and(ok, @eq(bytes_index_of(bytes, "abc"), 2))
    ok = @and(ok, @eq(bytes_last_index_of(bytes, "abc"), 6))
    if ok return
}

test "bytes invalid slice" {
    bad = bytes_slice("abc", 3, 2)
    if @eq(bad, BytesInvalidRange) return
}
