UrlError = @lib("url.do", UrlError)
UrlInvalidEscape = @lib("url.do", UrlInvalidEscape)
url_decode = @lib("url.do", url_decode)

url_bytes_eq(value [u8] | UrlError, expect [u8]) -> bool {
    if @is(value, UrlError) return false
    return @eq(value, expect)
}

url_is_invalid_escape(value [u8] | UrlError) -> bool {
    if @is(value, UrlError) return @eq(value, UrlInvalidEscape)
    return false
}

test "url decode helpers" {
    plain = url_decode("abc-._~")
    escaped = url_decode("a%20b%3F")
    lower = url_decode("%7e")
    bad_short = url_decode("%2")
    bad_digit = url_decode("%zz")

    ok bool = true
    ok = @and(ok, url_bytes_eq(plain, "abc-._~"))
    ok = @and(ok, url_bytes_eq(escaped, "a b?"))
    ok = @and(ok, url_bytes_eq(lower, "~"))
    ok = @and(ok, url_is_invalid_escape(bad_short))
    ok = @and(ok, url_is_invalid_escape(bad_digit))
    if ok return
}
