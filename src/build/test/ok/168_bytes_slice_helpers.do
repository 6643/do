BytesError = @lib("bytes.do", BytesError)
BytesOutOfBounds = @lib("bytes.do", BytesOutOfBounds)
BytesInvalidRange = @lib("bytes.do", BytesInvalidRange)
bytes_slice = @lib("bytes.do", slice)
bytes_slice_or = @lib("bytes.do", slice_or)
bytes_take = @lib("bytes.do", take)
bytes_take_or = @lib("bytes.do", take_or)
bytes_drop = @lib("bytes.do", drop)
bytes_drop_or = @lib("bytes.do", drop_or)

bytes_eq(value [u8] | BytesError, expect [u8]) -> bool {
    if @is(value, BytesError) return false
    return @eq(value, expect)
}

bytes_is_out_of_bounds(value [u8] | BytesError) -> bool {
    if @is(value, BytesError) return @eq(value, BytesOutOfBounds)
    return false
}

bytes_is_invalid_range(value [u8] | BytesError) -> bool {
    if @is(value, BytesError) return @eq(value, BytesInvalidRange)
    return false
}

test "bytes slice helpers" {
    sliced = bytes_slice("abcdef", 1, 4)
    bad_range = bytes_slice("abcdef", 5, 2)
    bad_oob = bytes_slice("abcdef", 1, 7)
    part, part_ok = bytes_slice_or("abcdef", 1, 4, "fallback")
    bad_part, bad_part_ok = bytes_slice_or("abcdef", 5, 2, "fallback")
    head = bytes_take("abcdef", 2)
    bad_head = bytes_take("abc", 9)
    head_or, head_or_ok = bytes_take_or("abc", 9, "fallback")
    tail = bytes_drop("abcdef", 2)
    bad_tail = bytes_drop("abc", 9)
    tail_or, tail_or_ok = bytes_drop_or("abc", 9, "fallback")

    ok bool = true
    ok = @and(ok, bytes_eq(sliced, "bcd"))
    ok = @and(ok, bytes_is_invalid_range(bad_range))
    ok = @and(ok, bytes_is_out_of_bounds(bad_oob))
    ok = @and(ok, part_ok)
    ok = @and(ok, @eq(part, "bcd"))
    ok = @and(ok, @not(bad_part_ok))
    ok = @and(ok, @eq(bad_part, "fallback"))
    ok = @and(ok, bytes_eq(head, "ab"))
    ok = @and(ok, bytes_is_out_of_bounds(bad_head))
    ok = @and(ok, @not(head_or_ok))
    ok = @and(ok, @eq(head_or, "fallback"))
    ok = @and(ok, bytes_eq(tail, "cdef"))
    ok = @and(ok, bytes_is_out_of_bounds(bad_tail))
    ok = @and(ok, @not(tail_or_ok))
    ok = @and(ok, @eq(tail_or, "fallback"))
    if ok return
}
