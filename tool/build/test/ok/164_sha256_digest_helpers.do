hex_encode = @lib("hex.do", encode)
sha256_sum = @lib("sha256.do", sum)

test "sha256 digest helpers" {
    abc_digest [u8] = sha256_sum("abc")
    empty_digest [u8] = sha256_sum("")
    abc [u8] = hex_encode(abc_digest)
    empty [u8] = hex_encode(empty_digest)

    ok bool = true
    ok = @and(ok, @eq(abc, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    ok = @and(ok, @eq(empty, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
    if ok return
}
