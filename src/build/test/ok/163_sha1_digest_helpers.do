hex_encode = @lib("hex.do", encode)
sha1_sum = @lib("sha1.do", sum)

test "sha1 digest helpers" {
    abc_digest [u8] = sha1_sum("abc")
    empty_digest [u8] = sha1_sum("")
    abc [u8] = hex_encode(abc_digest)
    empty [u8] = hex_encode(empty_digest)

    ok bool = true
    ok = @and(ok, @eq(abc, "a9993e364706816aba3e25717850c26c9cd0d89d"))
    ok = @and(ok, @eq(empty, "da39a3ee5e6b4b0d3255bfef95601890afd80709"))
    if ok return
}
