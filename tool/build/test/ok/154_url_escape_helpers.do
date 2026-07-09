url_encode = @lib("url.do", url_encode)

test "url escape helpers" {
    encoded [u8] = url_encode("a b?")

    ok bool = true
    ok = @and(ok, @eq(encoded, "a%20b%3F"))
    ok = @and(ok, @eq(url_encode("abc-._~"), "abc-._~"))
    if ok return
}
