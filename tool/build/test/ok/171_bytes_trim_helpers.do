bytes_trim_left_byte = @lib("bytes.do", trim_left_byte)
bytes_trim_byte = @lib("bytes.do", trim_byte)
bytes_trim_right_byte = @lib("bytes.do", trim_right_byte)

test "bytes trim helpers" {
    left_trimmed [u8] = bytes_trim_left_byte("  hello  ", 32)
    trimmed [u8] = bytes_trim_byte("  hello  ", 32)
    right_trimmed [u8] = bytes_trim_right_byte("  hello  ", 32)
    all_left [u8] = bytes_trim_left_byte("   ", 32)
    all_both [u8] = bytes_trim_byte("   ", 32)
    all_right [u8] = bytes_trim_right_byte("   ", 32)

    ok bool = true
    ok = @and(ok, @eq(left_trimmed, "hello  "))
    ok = @and(ok, @eq(trimmed, "hello"))
    ok = @and(ok, @eq(right_trimmed, "  hello"))
    ok = @and(ok, @eq(all_left, ""))
    ok = @and(ok, @eq(all_both, ""))
    ok = @and(ok, @eq(all_right, ""))
    if ok return
}
