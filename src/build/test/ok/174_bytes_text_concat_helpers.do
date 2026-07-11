bytes_concat = @lib("bytes.do", concat)
text_concat = @lib("text.do", concat)

test "bytes text concat helpers" {
    bytes_joined [u8] = bytes_concat("ab", "cd", "ef")
    bytes_pair [u8] = bytes_concat("ab", "cd")
    text_joined [u8] = text_concat("ab", "cd", "ef")
    text_pair [u8] = text_concat("ab", "cd")

    ok bool = true
    ok = @and(ok, @eq(bytes_joined, "abcdef"))
    ok = @and(ok, @eq(bytes_pair, "abcd"))
    ok = @and(ok, @eq(text_joined, "abcdef"))
    ok = @and(ok, @eq(text_pair, "abcd"))
    if ok return
}
