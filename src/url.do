UrlError error = UrlInvalidEscape

_percent u8 = 37
_dash u8 = 45
_dot u8 = 46
_zero u8 = 48
_nine u8 = 57
_a u8 = 65
_f u8 = 70
_z u8 = 90
_underscore u8 = 95
_lower_a u8 = 97
_lower_f u8 = 102
_lower_z u8 = 122
_tilde u8 = 126

.is_alpha_num(c u8) -> bool {
    if and(ge(c, _zero), le(c, _nine)) return true
    if and(ge(c, _a), le(c, _z)) return true
    if and(ge(c, _lower_a), le(c, _lower_z)) return true
    return false
}

.is_unreserved(c u8) -> bool {
    if is_alpha_num(c) return true
    if eq(c, _dash) return true
    if eq(c, _dot) return true
    if eq(c, _underscore) return true
    if eq(c, _tilde) return true
    return false
}

.hex_digit(value u8) -> u8 {
    if lt(value, 10) return add(_zero, value)
    return add(_a, sub(value, 10))
}

.hex_value(c u8) -> u8 | UrlError {
    if and(ge(c, _zero), le(c, _nine)) return sub(c, _zero)
    if and(ge(c, _a), le(c, _f)) return add(10, sub(c, _a))
    if and(ge(c, _lower_a), le(c, _lower_f)) return add(10, sub(c, _lower_a))
    return UrlInvalidEscape
}

url_encode(text [u8]) -> [u8] {
    out [u8] = .{}
    loop byte, _ = text {
        if is_unreserved(byte) {
            out = put(out, byte)
        } else {
            out = put(out, _percent, hex_digit(to_u8(div(byte, 16))), hex_digit(to_u8(rem(byte, 16))))
        }
    }
    return out
}

url_decode(text [u8]) -> [u8] | UrlError {
    out [u8] = .{}
    i usize = 0
    loop {
        if ge(i, len(text)) return out
        byte u8 = get(text, i)
        if ne(byte, _percent) {
            out = put(out, byte)
            i = add(i, 1)
        } else {
            if ge(add(i, 2), len(text)) return UrlInvalidEscape
            hi = hex_value(get(text, add(i, 1)))
            if is(hi, UrlError) return hi
            lo = hex_value(get(text, add(i, 2)))
            if is(lo, UrlError) return lo
            out = put(out, add(mul(hi, 16), lo))
            i = add(i, 3)
        }
    }
}
