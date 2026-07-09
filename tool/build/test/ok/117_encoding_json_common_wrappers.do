Base64Error = @lib("base64.do", Base64Error)
Base64BadLength = @lib("base64.do", InvalidLength)
base64_decode = @lib("base64.do", decode)
base64_decode_raw = @lib("base64.do", decode_raw)
base64_decode_raw_url = @lib("base64.do", decode_raw_url)
base64_decode_url = @lib("base64.do", decode_url)
base64_encode = @lib("base64.do", encode)
base64_encode_raw = @lib("base64.do", encode_raw)
base64_encode_raw_url = @lib("base64.do", encode_raw_url)
base64_encode_url = @lib("base64.do", encode_url)

HexError = @lib("hex.do", HexError)
HexBadLength = @lib("hex.do", InvalidLength)
hex_decode = @lib("hex.do", decode)
hex_encode = @lib("hex.do", encode)
hex_encode_upper = @lib("hex.do", encode_upper)

JsonError = @lib("json.do", JsonError)
JsonBadEscape = @lib("json.do", InvalidEscape)
json_escape = @lib("json.do", escape)
json_quote = @lib("json.do", quote)
json_unescape = @lib("json.do", unescape)

base64_bytes_eq(value [u8] | Base64Error, expect [u8]) -> bool {
    if @is(value, Base64Error) return false
    return @eq(value, expect)
}

base64_is_bad_length(value [u8] | Base64Error) -> bool {
    if @is(value, Base64Error) return @eq(value, Base64BadLength)
    return false
}

hex_bytes_eq(value [u8] | HexError, expect [u8]) -> bool {
    if @is(value, HexError) return false
    return @eq(value, expect)
}

hex_is_bad_length(value [u8] | HexError) -> bool {
    if @is(value, HexError) return @eq(value, HexBadLength)
    return false
}

json_bytes_eq(value [u8] | JsonError, expect [u8]) -> bool {
    if @is(value, JsonError) return false
    return @eq(value, expect)
}

json_is_bad_escape(value [u8] | JsonError) -> bool {
    if @is(value, JsonError) return @eq(value, JsonBadEscape)
    return false
}

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
    ok = @and(ok, @eq(b64, "aGVsbG8="))
    ok = @and(ok, @eq(b64_raw, "aGVsbG8"))
    ok = @and(ok, @eq(b64_url, "-_8="))
    ok = @and(ok, @eq(b64_raw_url, "-_8"))
    ok = @and(ok, base64_bytes_eq(b64_dec, "hello"))
    ok = @and(ok, base64_bytes_eq(b64_raw_dec, "hello"))
    ok = @and(ok, base64_bytes_eq(b64_url_dec, .{251, 255}))
    ok = @and(ok, base64_bytes_eq(b64_raw_url_dec, .{251, 255}))
    ok = @and(ok, base64_is_bad_length(b64_bad))
    ok = @and(ok, @eq(hex, "000fff"))
    ok = @and(ok, @eq(hex_upper, "000FFF"))
    ok = @and(ok, hex_bytes_eq(hex_dec, .{0, 15, 255}))
    ok = @and(ok, hex_is_bad_length(hex_bad))
    ok = @and(ok, @eq(escaped, "a\\\"b\\\\c\\n"))
    ok = @and(ok, @eq(quoted, "\"a\\\"\""))
    ok = @and(ok, json_bytes_eq(unescaped, "a\"b\\c\n"))
    ok = @and(ok, json_is_bad_escape(json_bad))
    if ok return
}
