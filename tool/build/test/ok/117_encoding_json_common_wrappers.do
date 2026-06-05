Base64Error = @base64.do/Base64Error
Base64BadLength = @base64.do/InvalidLength
base64_decode = @base64.do/decode
base64_decode_raw = @base64.do/decode_raw
base64_decode_raw_url = @base64.do/decode_raw_url
base64_decode_url = @base64.do/decode_url
base64_encode = @base64.do/encode
base64_encode_raw = @base64.do/encode_raw
base64_encode_raw_url = @base64.do/encode_raw_url
base64_encode_url = @base64.do/encode_url

HexError = @hex.do/HexError
HexBadLength = @hex.do/InvalidLength
hex_decode = @hex.do/decode
hex_encode = @hex.do/encode
hex_encode_upper = @hex.do/encode_upper

JsonError = @json.do/JsonError
JsonBadEscape = @json.do/InvalidEscape
json_escape = @json.do/escape
json_quote = @json.do/quote
json_unescape = @json.do/unescape

test "hex base64 json common wrappers" {
    b64 [u8] = base64_encode("hello")
    b64_raw [u8] = base64_encode_raw("hello")
    b64_url [u8] = base64_encode_url(.{251, 255})
    b64_raw_url [u8] = base64_encode_raw_url(.{251, 255})
    b64_dec = base64_decode(b64)
    b64_raw_dec = base64_decode_raw(b64_raw)
    b64_url_dec = base64_decode_url(b64_url)
    b64_raw_url_dec = base64_decode_raw_url(b64_raw_url)
    b64_bad = base64_decode("x")

    hex [u8] = hex_encode(.{0, 15, 255})
    hex_upper [u8] = hex_encode_upper(.{0, 15, 255})
    hex_dec = hex_decode(hex)
    hex_bad = hex_decode("f")

    escaped [u8] = json_escape("a\"b\\c\n")
    quoted [u8] = json_quote("a\"")
    unescaped = json_unescape("a\\\"b\\\\c\\n")
    json_bad = json_unescape("\\x")

    ok bool = true
    ok = and(ok, eq(b64, "aGVsbG8="))
    ok = and(ok, eq(b64_raw, "aGVsbG8"))
    ok = and(ok, eq(b64_url, "-_8="))
    ok = and(ok, eq(b64_raw_url, "-_8"))
    ok = and(ok, eq(b64_dec, "hello"))
    ok = and(ok, eq(b64_raw_dec, "hello"))
    ok = and(ok, eq(b64_url_dec, .{251, 255}))
    ok = and(ok, eq(b64_raw_url_dec, .{251, 255}))
    ok = and(ok, eq(b64_bad, Base64BadLength))
    ok = and(ok, eq(hex, "000fff"))
    ok = and(ok, eq(hex_upper, "000FFF"))
    ok = and(ok, eq(hex_dec, .{0, 15, 255}))
    ok = and(ok, eq(hex_bad, HexBadLength))
    ok = and(ok, eq(escaped, "a\\\"b\\\\c\\n"))
    ok = and(ok, eq(quoted, "\"a\\\"\""))
    ok = and(ok, eq(unescaped, "a\"b\\c\n"))
    ok = and(ok, eq(json_bad, JsonBadEscape))
    if ok return
}
