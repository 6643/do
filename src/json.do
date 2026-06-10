JsonError error = InvalidEscape | UnterminatedEscape

_quote u8 = 34
_slash u8 = 47
_backslash u8 = 92
_backspace u8 = 8
_form_feed u8 = 12
_newline u8 = 10
_carriage u8 = 13
_tab u8 = 9
_zero u8 = 48
_nine u8 = 57
_upper_a u8 = 65
_upper_f u8 = 70
_lower_a u8 = 97
_lower_f u8 = 102

.append_bytes(out [u8], part [u8]) -> [u8] {
    next [u8] = out
    loop byte, _ = part {
        next = @put(next, byte)
    }
    return next
}

.text_bytes(value text) -> [u8] {
    return value
}

.hex_digit(value u8) -> u8 {
    if @lt(value, 10) return @add(_zero, value)
    return @add(_upper_a, @sub(value, 10))
}

.hex_value(byte u8) -> u16 | JsonError {
    if @and(@ge(byte, _zero), @le(byte, _nine)) return @to_u16(@sub(byte, _zero))
    if @and(@ge(byte, _upper_a), @le(byte, _upper_f)) return @to_u16(@add(@sub(byte, _upper_a), 10))
    if @and(@ge(byte, _lower_a), @le(byte, _lower_f)) return @to_u16(@add(@sub(byte, _lower_a), 10))
    return InvalidEscape
}

.append_unicode_escape(out [u8], byte u8) -> [u8] {
    out = @put(out, _backslash, 117, 48, 48, hex_digit(@to_u8(@div(byte, 16))), hex_digit(@to_u8(@rem(byte, 16))))
    return out
}

.is_high_surrogate(unit u16) -> bool {
    return @and(@ge(unit, 55296), @le(unit, 56319))
}

.is_low_surrogate(unit u16) -> bool {
    return @and(@ge(unit, 56320), @le(unit, 57343))
}

.append_utf8(out [u8], code u32) -> [u8] | JsonError {
    if @le(code, 127) {
        out = @put(out, @to_u8(code))
        return out
    }
    if @le(code, 2047) {
        out = @put(out, @to_u8(@add(192, @div(code, 64))), @to_u8(@add(128, @rem(code, 64))))
        return out
    }
    if @and(@ge(code, 55296), @le(code, 57343)) return InvalidEscape
    if @le(code, 65535) {
        out = @put(out, @to_u8(@add(224, @div(code, 4096))), @to_u8(@add(128, @rem(@div(code, 64), 64))), @to_u8(@add(128, @rem(code, 64))))
        return out
    }
    if @le(code, 1114111) {
        out = @put(out, @to_u8(@add(240, @div(code, 262144))), @to_u8(@add(128, @rem(@div(code, 4096), 64))), @to_u8(@add(128, @rem(@div(code, 64), 64))), @to_u8(@add(128, @rem(code, 64))))
        return out
    }
    return InvalidEscape
}

.decode_hex4(bytes [u8], offset usize) -> u16 | JsonError {
    if @gt(@add(offset, 4), @len(bytes)) return UnterminatedEscape
    h0 = hex_value(@get(bytes, offset))
    if @is(h0, JsonError) return h0
    h1 = hex_value(@get(bytes, @add(offset, 1)))
    if @is(h1, JsonError) return h1
    h2 = hex_value(@get(bytes, @add(offset, 2)))
    if @is(h2, JsonError) return h2
    h3 = hex_value(@get(bytes, @add(offset, 3)))
    if @is(h3, JsonError) return h3
    return @add(@mul(h0, 4096), @mul(h1, 256), @mul(h2, 16), h3)
}

escape(bytes [u8]) -> [u8] {
    out [u8] = .{}
    i usize = 0
    loop {
        if @eq(i, @len(bytes)) return out
        ch u8 = @get(bytes, i)
        if @eq(ch, _quote) {
            out = @put(out, _backslash, _quote)
        } else if @eq(ch, _backslash) {
            out = @put(out, _backslash, _backslash)
        } else if @eq(ch, _backspace) {
            out = @put(out, _backslash, 98)
        } else if @eq(ch, _form_feed) {
            out = @put(out, _backslash, 102)
        } else if @eq(ch, _newline) {
            out = @put(out, _backslash, 110)
        } else if @eq(ch, _carriage) {
            out = @put(out, _backslash, 114)
        } else if @eq(ch, _tab) {
            out = @put(out, _backslash, 116)
        } else if @lt(ch, 32) {
            out = append_unicode_escape(out, ch)
        } else {
            out = @put(out, ch)
        }
        i = @add(i, 1)
    }
}

quote(bytes [u8]) -> [u8] {
    out [u8] = .{}
    out = @put(out, _quote)
    escaped [u8] = escape(bytes)
    loop byte, _ = escaped {
        out = @put(out, byte)
    }
    out = @put(out, _quote)
    return out
}

.append_u32(out [u8], value u32) -> [u8] {
    if @eq(value, 0) {
        out = @put(out, _zero)
        return out
    }

    digits [u8] = .{}
    n u32 = value
    loop {
        if @eq(n, 0) {
            i usize = @len(digits)
            loop {
                if @eq(i, 0) return out
                i = @sub(i, 1)
                out = @put(out, @get(digits, i))
            }
        }
        digit u8 = @to_u8(@rem(n, 10))
        digits = @put(digits, @add(_zero, digit))
        n = @div(n, 10)
    }
}

.encode_value(value i32) -> [u8] {
    out [u8] = .{}
    if @eq(value, -2147483648) return "-2147483648"
    if @lt(value, 0) {
        out = @put(out, 45)
        return append_u32(out, @to_u32(@sub(0, value)))
    }
    return append_u32(out, @to_u32(value))
}

.encode_value(value text) -> [u8] {
    return quote(text_bytes(value))
}

.encode_value(value [u8]) -> [u8] {
    return quote(value)
}

.encode_value(value bool) -> [u8] {
    if value return "true"
    return "false"
}

#T
stringify(value T) -> [u8] {
    out [u8] = .{}
    out = @put(out, 123)
    first bool = true
    loop field = fields(T) {
        if first {
            first = false
        } else {
            out = @put(out, 44)
        }
        out = append_bytes(out, quote(text_bytes(@field_name(field))))
        out = @put(out, 58)
        out = append_bytes(out, encode_value(@field_get(value, field)))
    }
    out = @put(out, 125)
    return out
}

unescape(bytes [u8]) -> [u8] | JsonError {
    out [u8] = .{}
    i usize = 0
    loop {
        if @eq(i, @len(bytes)) return out
        ch u8 = @get(bytes, i)
        if @ne(ch, _backslash) {
            if @lt(ch, 32) return InvalidEscape
            out = @put(out, ch)
            i = @add(i, 1)
            continue
        }

        if @eq(@add(i, 1), @len(bytes)) return UnterminatedEscape
        next u8 = @get(bytes, @add(i, 1))
        if @eq(next, _quote) {
            out = @put(out, _quote)
        } else if @eq(next, _backslash) {
            out = @put(out, _backslash)
        } else if @eq(next, _slash) {
            out = @put(out, _slash)
        } else if @eq(next, 98) {
            out = @put(out, _backspace)
        } else if @eq(next, 102) {
            out = @put(out, _form_feed)
        } else if @eq(next, 110) {
            out = @put(out, _newline)
        } else if @eq(next, 114) {
            out = @put(out, _carriage)
        } else if @eq(next, 116) {
            out = @put(out, _tab)
        } else if @eq(next, 117) {
            unit = decode_hex4(bytes, @add(i, 2))
            if @is(unit, JsonError) return unit
            if is_high_surrogate(unit) {
                if @or(@ge(@add(i, 7), @len(bytes)), @ne(@get(bytes, @add(i, 6)), _backslash), @ne(@get(bytes, @add(i, 7)), 117)) return InvalidEscape
                low = decode_hex4(bytes, @add(i, 8))
                if @is(low, JsonError) return low
                if @not(is_low_surrogate(low)) return InvalidEscape
                code u32 = @add(65536, @mul(@to_u32(@sub(unit, 55296)), 1024), @to_u32(@sub(low, 56320)))
                encoded = append_utf8(out, code)
                if @is(encoded, JsonError) return encoded
                out = encoded
                i = @add(i, 12)
                continue
            }
            if is_low_surrogate(unit) return InvalidEscape
            encoded = append_utf8(out, @to_u32(unit))
            if @is(encoded, JsonError) return encoded
            out = encoded
            i = @add(i, 6)
            continue
        } else {
            return InvalidEscape
        }
        i = @add(i, 2)
    }
}
