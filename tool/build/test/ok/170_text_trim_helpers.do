text_trim_left_byte = @lib("text.do", trim_left_byte)
text_trim_byte = @lib("text.do", trim_byte)
text_trim_right_byte = @lib("text.do", trim_right_byte)

test "text trim helpers" {
    left_trimmed [u8] = text_trim_left_byte("  hello  ", 32)
    trimmed [u8] = text_trim_byte("  hello  ", 32)
    right_trimmed [u8] = text_trim_right_byte("  hello  ", 32)
    all_left [u8] = text_trim_left_byte("   ", 32)
    all_both [u8] = text_trim_byte("   ", 32)
    all_right [u8] = text_trim_right_byte("   ", 32)

    ok bool = true
    ok = @and(ok, @eq(left_trimmed, "hello  "))
    ok = @and(ok, @eq(trimmed, "hello"))
    ok = @and(ok, @eq(right_trimmed, "  hello"))
    ok = @and(ok, @eq(all_left, ""))
    ok = @and(ok, @eq(all_both, ""))
    ok = @and(ok, @eq(all_right, ""))
    if ok return
}
