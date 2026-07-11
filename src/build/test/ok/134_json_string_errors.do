JsonBadEscape = @lib("json.do", InvalidEscape)
JsonUnterminated = @lib("json.do", UnterminatedEscape)
json_unescape = @lib("json.do", unescape)

test "json string invalid escapes" {
    bad_escape_input [u8] = .{92, 120}
    dangling_input [u8] = .{92}
    short_unicode_input [u8] = .{92, 117, 48, 48}
    bad_hex_input [u8] = .{92, 117, 48, 48, 71, 48}
    raw_control_input [u8] = .{31}
    high_surrogate_input [u8] = "\\uD800"
    low_surrogate_input [u8] = "\\uDC00"

    bad_escape = json_unescape(bad_escape_input)
    dangling = json_unescape(dangling_input)
    short_unicode = json_unescape(short_unicode_input)
    bad_hex = json_unescape(bad_hex_input)
    raw_control = json_unescape(raw_control_input)
    high_surrogate = json_unescape(high_surrogate_input)
    low_surrogate = json_unescape(low_surrogate_input)

    ok bool = true
    ok = @and(ok, @eq(bad_escape, JsonBadEscape))
    ok = @and(ok, @eq(dangling, JsonUnterminated))
    ok = @and(ok, @eq(short_unicode, JsonUnterminated))
    ok = @and(ok, @eq(bad_hex, JsonBadEscape))
    ok = @and(ok, @eq(raw_control, JsonBadEscape))
    ok = @and(ok, @eq(high_surrogate, JsonBadEscape))
    ok = @and(ok, @eq(low_surrogate, JsonBadEscape))
    if ok return
}
