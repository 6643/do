Utf8Error = @lib("utf8.do", Utf8Error)
Utf8Decode = @lib("utf8.do", Utf8Decode)
Utf8InvalidContinuation = @lib("utf8.do", Utf8InvalidContinuation)
utf8_code_at = @lib("utf8.do", code_at)
utf8_count = @lib("utf8.do", count)
utf8_decode_at = @lib("utf8.do", decode_at)
utf8_encode = @lib("utf8.do", encode)
utf8_is_valid = @lib("utf8.do", is_valid)
utf8_size_at = @lib("utf8.do", size_at)
utf8_validate = @lib("utf8.do", validate)

Utf16Error = @lib("utf16.do", Utf16Error)
Utf16Decode = @lib("utf16.do", Utf16Decode)
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
    valid = utf8_validate(bytes)
    count = utf8_count(bytes)
    code0 = utf8_code_at(bytes, 0)
    size0 = utf8_size_at(bytes, 0)
    code1 = utf8_code_at(bytes, 1)
    size1 = utf8_size_at(bytes, 1)
    code2 = utf8_code_at(bytes, 4)
    size2 = utf8_size_at(bytes, 4)

    ok bool = true
    ok = @and(ok, utf8_is_valid(bytes))
    ok = @and(ok, @eq(valid, nil))
    if @is(d0, Utf8Decode) {
        ok = @and(ok, @eq(@get(d0, .code), 97))
        ok = @and(ok, @eq(@get(d0, .size), 1))
    } else {
        ok = false
    }
    if @is(d1, Utf8Decode) {
        ok = @and(ok, @eq(@get(d1, .code), 8364))
        ok = @and(ok, @eq(@get(d1, .size), 3))
    } else {
        ok = false
    }
    if @is(d2, Utf8Decode) {
        ok = @and(ok, @eq(@get(d2, .code), 128512))
        ok = @and(ok, @eq(@get(d2, .size), 4))
    } else {
        ok = false
    }
    if @is(count, usize) {
        ok = @and(ok, @eq(count, 3))
    } else {
        ok = false
    }
    if @is(code0, u32) {
        ok = @and(ok, @eq(code0, 97))
    } else {
        ok = false
    }
    if @is(size0, usize) {
        ok = @and(ok, @eq(size0, 1))
    } else {
        ok = false
    }
    if @is(code1, u32) {
        ok = @and(ok, @eq(code1, 8364))
    } else {
        ok = false
    }
    if @is(size1, usize) {
        ok = @and(ok, @eq(size1, 3))
    } else {
        ok = false
    }
    if @is(code2, u32) {
        ok = @and(ok, @eq(code2, 128512))
    } else {
        ok = false
    }
    if @is(size2, usize) {
        ok = @and(ok, @eq(size2, 4))
    } else {
        ok = false
    }
    if @is(encoded, [u8]) {
        ok = @and(ok, @eq(encoded, "😀"))
    } else {
        ok = false
    }
    if ok return
}

test "utf8 invalid bytes" {
    bad [u8] = .{226, 40, 161}
    err = utf8_validate(bad)
    if @is(err, Utf8Error) {
        if @eq(err, Utf8InvalidContinuation) return
    }
}

test "utf16 validate decode encode" {
    units [u16] = .{65, 55357, 56832}
    d0 = utf16_decode_at(units, 0)
    d1 = utf16_decode_at(units, 1)
    encoded = utf16_encode(128512)
    valid = utf16_validate(units)
    count = utf16_count(units)
    code0 = utf16_code_at(units, 0)
    size0 = utf16_size_at(units, 0)
    code1 = utf16_code_at(units, 1)
    size1 = utf16_size_at(units, 1)

    ok bool = true
    ok = @and(ok, utf16_is_valid(units))
    ok = @and(ok, @eq(valid, nil))
    if @is(d0, Utf16Decode) {
        ok = @and(ok, @eq(@get(d0, .code), 65))
        ok = @and(ok, @eq(@get(d0, .size), 1))
    } else {
        ok = false
    }
    if @is(d1, Utf16Decode) {
        ok = @and(ok, @eq(@get(d1, .code), 128512))
        ok = @and(ok, @eq(@get(d1, .size), 2))
    } else {
        ok = false
    }
    if @is(count, usize) {
        ok = @and(ok, @eq(count, 2))
    } else {
        ok = false
    }
    if @is(code0, u32) {
        ok = @and(ok, @eq(code0, 65))
    } else {
        ok = false
    }
    if @is(size0, usize) {
        ok = @and(ok, @eq(size0, 1))
    } else {
        ok = false
    }
    if @is(code1, u32) {
        ok = @and(ok, @eq(code1, 128512))
    } else {
        ok = false
    }
    if @is(size1, usize) {
        ok = @and(ok, @eq(size1, 2))
    } else {
        ok = false
    }
    if @is(encoded, [u16]) {
        ok = @and(ok, @eq(@len(encoded), 2))
        ok = @and(ok, @eq(@get(encoded, 0), 55357))
        ok = @and(ok, @eq(@get(encoded, 1), 56832))
    } else {
        ok = false
    }
    if ok return
}

test "utf16 invalid surrogate" {
    bad [u16] = .{56832}
    err = utf16_validate(bad)
    if @is(err, Utf16Error) {
        if @eq(err, Utf16UnpairedSurrogate) return
    }
}
