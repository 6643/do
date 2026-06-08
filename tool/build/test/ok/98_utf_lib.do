Utf8Error = @lib("utf8.do", Utf8Error)
Utf8InvalidContinuation = @lib("utf8.do", Utf8InvalidContinuation)
utf8_code_at = @lib("utf8.do", code_at)
utf8_count = @lib("utf8.do", count)
utf8_decode_at = @lib("utf8.do", decode_at)
utf8_encode = @lib("utf8.do", encode)
utf8_is_valid = @lib("utf8.do", is_valid)
utf8_size_at = @lib("utf8.do", size_at)
utf8_validate = @lib("utf8.do", validate)

Utf16Error = @lib("utf16.do", Utf16Error)
Utf16UnpairedSurrogate = @lib("utf16.do", Utf16UnpairedSurrogate)
utf16_code_at = @lib("utf16.do", code_at)
utf16_count = @lib("utf16.do", count)
utf16_decode_at = @lib("utf16.do", decode_at)
utf16_encode = @lib("utf16.do", encode)
utf16_is_valid = @lib("utf16.do", is_valid)
utf16_size_at = @lib("utf16.do", size_at)
utf16_validate = @lib("utf16.do", validate)

test "utf8 validate decode encode" {
    bytes [u8] = "a€😀"
    d0 = utf8_decode_at(bytes, 0)
    d1 = utf8_decode_at(bytes, 1)
    d2 = utf8_decode_at(bytes, 4)
    encoded = utf8_encode(128512)

    ok bool = true
    ok = @and(ok, utf8_is_valid(bytes))
    ok = @and(ok, @eq(utf8_validate(bytes), nil))
    ok = @and(ok, @eq(utf8_count(bytes), 3))
    ok = @and(ok, @eq(utf8_code_at(bytes, 0), 97))
    ok = @and(ok, @eq(utf8_size_at(bytes, 0), 1))
    ok = @and(ok, @eq(utf8_code_at(bytes, 1), 8364))
    ok = @and(ok, @eq(utf8_size_at(bytes, 1), 3))
    ok = @and(ok, @eq(utf8_code_at(bytes, 4), 128512))
    ok = @and(ok, @eq(utf8_size_at(bytes, 4), 4))
    ok = @and(ok, @eq(encoded, "😀"))
    if ok return
}

test "utf8 invalid bytes" {
    bad [u8] = .{226, 40, 161}
    err = utf8_validate(bad)
    if @eq(err, Utf8InvalidContinuation) return
}

test "utf16 validate decode encode" {
    units [u16] = .{65, 55357, 56832}
    d0 = utf16_decode_at(units, 0)
    d1 = utf16_decode_at(units, 1)
    encoded = utf16_encode(128512)

    ok bool = true
    ok = @and(ok, utf16_is_valid(units))
    ok = @and(ok, @eq(utf16_validate(units), nil))
    ok = @and(ok, @eq(utf16_count(units), 2))
    ok = @and(ok, @eq(utf16_code_at(units, 0), 65))
    ok = @and(ok, @eq(utf16_size_at(units, 0), 1))
    ok = @and(ok, @eq(utf16_code_at(units, 1), 128512))
    ok = @and(ok, @eq(utf16_size_at(units, 1), 2))
    ok = @and(ok, @eq(@len(encoded), 2))
    ok = @and(ok, @eq(@get(encoded, 0), 55357))
    ok = @and(ok, @eq(@get(encoded, 1), 56832))
    if ok return
}

test "utf16 invalid surrogate" {
    bad [u16] = .{56832}
    err = utf16_validate(bad)
    if @eq(err, Utf16UnpairedSurrogate) return
}
