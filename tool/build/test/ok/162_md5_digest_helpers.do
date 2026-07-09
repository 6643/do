hex_encode = @lib("hex.do", encode)
md5_sum = @lib("md5.do", sum)

test "md5 digest helpers" {
    abc_digest [u8] = md5_sum("abc")
    empty_digest [u8] = md5_sum("")
    abc [u8] = hex_encode(abc_digest)
    empty [u8] = hex_encode(empty_digest)

    ok bool = true
    ok = @and(ok, @eq(abc, "900150983cd24fb0d6963f7d28e17f72"))
    ok = @and(ok, @eq(empty, "d41d8cd98f00b204e9800998ecf8427e"))
    if ok return
}
