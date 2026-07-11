Base64Error = @lib("base64.do", Base64Error)
base64_decode = @lib("base64.do", decode)
base64_decode_raw = @lib("base64.do", decode_raw)
base64_decode_url = @lib("base64.do", decode_url)
base64_decode_raw_url = @lib("base64.do", decode_raw_url)

base64_bytes_eq(value [u8] | Base64Error, expect [u8]) -> bool {
    if @is(value, Base64Error) return false
    return @eq(value, expect)
}

test "base64 decode helpers" {
    decoded = base64_decode("aGVsbG8=")
    decoded_raw = base64_decode_raw("aGVsbG8")
    decoded_url = base64_decode_url("-_8=")
    decoded_raw_url = base64_decode_raw_url("-_8")

    ok bool = true
    ok = @and(ok, base64_bytes_eq(decoded, "hello"))
    ok = @and(ok, base64_bytes_eq(decoded_raw, "hello"))
    ok = @and(ok, base64_bytes_eq(decoded_url, .{251, 255}))
    ok = @and(ok, base64_bytes_eq(decoded_raw_url, .{251, 255}))
    if ok return
}
