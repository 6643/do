base64_encode = @lib("base64.do", encode)
base64_encode_raw = @lib("base64.do", encode_raw)
base64_encode_url = @lib("base64.do", encode_url)
base64_encode_raw_url = @lib("base64.do", encode_raw_url)

test "base64 encode helpers" {
    ok bool = true
    ok = @and(ok, @eq(base64_encode(""), ""))
    ok = @and(ok, @eq(base64_encode("hello"), "aGVsbG8="))
    ok = @and(ok, @eq(base64_encode_raw("hello"), "aGVsbG8"))
    ok = @and(ok, @eq(base64_encode_url(.{251, 255}), "-_8="))
    ok = @and(ok, @eq(base64_encode_raw_url(.{251, 255}), "-_8"))
    if ok return
}
