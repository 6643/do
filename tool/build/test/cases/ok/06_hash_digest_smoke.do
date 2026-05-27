Text = @/text.do/Text
hex_encode = @/hex.do/encode
md5_sum = @/md5.do/sum
sha1_sum = @/sha1.do/sum
sha256_sum = @/sha256.do/sum

test "md5 digest abc" {
    expected Text = "900150983cd24fb0d6963f7d28e17f72"
    if eq(hex_encode(md5_sum("abc")), expected) return
}

test "sha1 digest abc" {
    expected Text = "a9993e364706816aba3e25717850c26c9cd0d89d"
    if eq(hex_encode(sha1_sum("abc")), expected) return
}

test "sha256 digest abc" {
    expected Text = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    if eq(hex_encode(sha256_sum("abc")), expected) return
}
