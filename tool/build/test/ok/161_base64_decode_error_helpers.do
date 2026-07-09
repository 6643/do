Base64Error = @lib("base64.do", Base64Error)
Base64InvalidLength = @lib("base64.do", InvalidLength)
Base64InvalidDigit = @lib("base64.do", InvalidDigit)
Base64InvalidPadding = @lib("base64.do", InvalidPadding)
base64_decode = @lib("base64.do", decode)
base64_decode_raw = @lib("base64.do", decode_raw)

base64_is_invalid_length(value [u8] | Base64Error) -> bool {
    if @is(value, Base64Error) return @eq(value, Base64InvalidLength)
    return false
}

base64_is_invalid_digit(value [u8] | Base64Error) -> bool {
    if @is(value, Base64Error) return @eq(value, Base64InvalidDigit)
    return false
}

base64_is_invalid_padding(value [u8] | Base64Error) -> bool {
    if @is(value, Base64Error) return @eq(value, Base64InvalidPadding)
    return false
}

test "base64 decode error helpers" {
    bad_len = base64_decode("x")
    bad_digit = base64_decode("!!!!")
    bad_padding = base64_decode_raw("AA==")

    ok bool = true
    ok = @and(ok, base64_is_invalid_length(bad_len))
    ok = @and(ok, base64_is_invalid_digit(bad_digit))
    ok = @and(ok, base64_is_invalid_padding(bad_padding))
    if ok return
}
