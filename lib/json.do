JsonError error = InvalidEscape | UnterminatedEscape | MaxDepth | InvalidJson | UnexpectedEnd | ExpectedObject | ExpectedField | ExpectedColon | ExpectedComma | ExpectedValue

_default_max_depth usize = 128

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
_upper_e u8 = 69
_lower_e u8 = 101
_plus u8 = 43
_minus u8 = 45
_dot u8 = 46
_comma u8 = 44
_colon u8 = 58
_open_bracket u8 = 91
_close_bracket u8 = 93
_open_brace u8 = 123
_close_brace u8 = 125

.is_ws(byte u8) -> bool {
    if @eq(byte, 32) return true
    if @eq(byte, _newline) return true
    if @eq(byte, _carriage) return true
    if @eq(byte, _tab) return true
    return false
}

.skip_ws(bytes [u8], offset usize) -> usize {
    i usize = offset
    loop {
        if @eq(i, @len(bytes)) return i
        if @not(is_ws(@get(bytes, i))) return i
        i = @add(i, 1)
    }
}

.is_digit(byte u8) -> bool {
    return @and(@ge(byte, _zero), @le(byte, _nine))
}

.bytes_eq(a [u8], b [u8]) -> bool {
    if @ne(@len(a), @len(b)) return false
    i usize = 0
    loop {
        if @eq(i, @len(a)) return true
        if @ne(@get(a, i), @get(b, i)) return false
        i = @add(i, 1)
    }
}

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
    if @and(@ge(byte, _zero), @le(byte, _nine)) return @as(u16, @sub(byte, _zero))
    if @and(@ge(byte, _upper_a), @le(byte, _upper_f)) return @as(u16, @add(@sub(byte, _upper_a), 10))
    if @and(@ge(byte, _lower_a), @le(byte, _lower_f)) return @as(u16, @add(@sub(byte, _lower_a), 10))
    return InvalidEscape
}

.append_unicode_escape(out [u8], byte u8) -> [u8] {
    out = @put(out, _backslash, 117, 48, 48, hex_digit(@as(u8, @div(byte, 16))), hex_digit(@as(u8, @rem(byte, 16))))
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
        out = @put(out, @as(u8, code))
        return out
    }
    if @le(code, 2047) {
        out = @put(out, @as(u8, @add(192, @div(code, 64))), @as(u8, @add(128, @rem(code, 64))))
        return out
    }
    if @and(@ge(code, 55296), @le(code, 57343)) return InvalidEscape
    if @le(code, 65535) {
        out = @put(out, @as(u8, @add(224, @div(code, 4096))), @as(u8, @add(128, @rem(@div(code, 64), 64))), @as(u8, @add(128, @rem(code, 64))))
        return out
    }
    if @le(code, 1114111) {
        out = @put(out, @as(u8, @add(240, @div(code, 262144))), @as(u8, @add(128, @rem(@div(code, 4096), 64))), @as(u8, @add(128, @rem(@div(code, 64), 64))), @as(u8, @add(128, @rem(code, 64))))
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
        digit u8 = @as(u8, @rem(n, 10))
        digits = @put(digits, @add(_zero, digit))
        n = @div(n, 10)
    }
}

.encode_value(value i32, depth usize) -> [u8] | JsonError {
    out [u8] = .{}
    if @eq(value, -2147483648) return "-2147483648"
    if @lt(value, 0) {
        out = @put(out, 45)
        return append_u32(out, @as(u32, @sub(0, value)))
    }
    return append_u32(out, @as(u32, value))
}

.encode_value(value u8, depth usize) -> [u8] | JsonError {
    out [u8] = .{}
    return append_u32(out, @as(u32, value))
}

.encode_value(value text, depth usize) -> [u8] | JsonError {
    return quote(text_bytes(value))
}

.encode_value(value [u8], depth usize) -> [u8] | JsonError {
    return quote(value)
}

.encode_value(value bool, depth usize) -> [u8] | JsonError {
    if value return "true"
    return "false"
}

#T
.encode_value(value T | nil, depth usize) -> [u8] | JsonError {
    if @eq(value, nil) return "null"
    return encode_value(value, depth)
}

#T
stringify(value T) -> [u8] | JsonError {
    return stringify_with_depth(value, _default_max_depth)
}

stringify(value i32) -> [u8] | JsonError {
    return stringify_with_depth(value, _default_max_depth)
}

stringify(value u8) -> [u8] | JsonError {
    return stringify_with_depth(value, _default_max_depth)
}

stringify(value text) -> [u8] | JsonError {
    return stringify_with_depth(value, _default_max_depth)
}

stringify(value [u8]) -> [u8] | JsonError {
    return stringify_with_depth(value, _default_max_depth)
}

stringify(value bool) -> [u8] | JsonError {
    return stringify_with_depth(value, _default_max_depth)
}

#T
stringify_with_depth(value T, max_depth usize) -> [u8] | JsonError {
    return stringify_depth(value, max_depth)
}

stringify_with_depth(value i32, max_depth usize) -> [u8] | JsonError {
    return encode_value(value, max_depth)
}

stringify_with_depth(value u8, max_depth usize) -> [u8] | JsonError {
    return encode_value(value, max_depth)
}

stringify_with_depth(value text, max_depth usize) -> [u8] | JsonError {
    return encode_value(value, max_depth)
}

stringify_with_depth(value [u8], max_depth usize) -> [u8] | JsonError {
    return encode_value(value, max_depth)
}

stringify_with_depth(value bool, max_depth usize) -> [u8] | JsonError {
    return encode_value(value, max_depth)
}

#T
.encode_value(value T, depth usize) -> [u8] | JsonError {
    return stringify_depth(value, depth)
}

#T
.stringify_depth(value T, depth usize) -> [u8] | JsonError {
    if @eq(depth, 0) return MaxDepth

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
        encoded = encode_value(@field_get(value, field), @sub(depth, 1))
        if @is(encoded, JsonError) return encoded
        out = append_bytes(out, encoded)
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
                code u32 = @add(65536, @mul(@as(u32, @sub(unit, 55296)), 1024), @as(u32, @sub(low, 56320)))
                encoded = append_utf8(out, code)
                if @is(encoded, JsonError) return encoded
                out = encoded
                i = @add(i, 12)
                continue
            }
            if is_low_surrogate(unit) return InvalidEscape
            encoded = append_utf8(out, @as(u32, unit))
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

.parse_string_token(bytes [u8], offset usize) -> [u8], usize, JsonError | nil {
    i usize = skip_ws(bytes, offset)
    if @ge(i, @len(bytes)) return .{}, i, UnexpectedEnd
    if @ne(@get(bytes, i), _quote) return .{}, i, ExpectedValue

    out [u8] = .{}
    i = @add(i, 1)
    loop {
        if @ge(i, @len(bytes)) return .{}, i, UnterminatedEscape
        ch u8 = @get(bytes, i)
        if @eq(ch, _quote) return out, @add(i, 1), nil
        if @ne(ch, _backslash) {
            if @lt(ch, 32) return .{}, i, InvalidEscape
            out = @put(out, ch)
            i = @add(i, 1)
            continue
        }

        if @eq(@add(i, 1), @len(bytes)) return .{}, i, UnterminatedEscape
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
            if @is(unit, JsonError) return .{}, i, unit
            if is_high_surrogate(unit) {
                if @or(@ge(@add(i, 7), @len(bytes)), @ne(@get(bytes, @add(i, 6)), _backslash), @ne(@get(bytes, @add(i, 7)), 117)) return .{}, i, InvalidEscape
                low = decode_hex4(bytes, @add(i, 8))
                if @is(low, JsonError) return .{}, i, low
                if @not(is_low_surrogate(low)) return .{}, i, InvalidEscape
                code u32 = @add(65536, @mul(@as(u32, @sub(unit, 55296)), 1024), @as(u32, @sub(low, 56320)))
                encoded = append_utf8(out, code)
                if @is(encoded, JsonError) return .{}, i, encoded
                out = encoded
                i = @add(i, 12)
                continue
            }
            if is_low_surrogate(unit) return .{}, i, InvalidEscape
            encoded = append_utf8(out, @as(u32, unit))
            if @is(encoded, JsonError) return .{}, i, encoded
            out = encoded
            i = @add(i, 6)
            continue
        } else {
            return .{}, i, InvalidEscape
        }
        i = @add(i, 2)
    }
}

.match_literal(bytes [u8], offset usize, lit [u8]) -> usize | JsonError {
    if @gt(@add(offset, @len(lit)), @len(bytes)) return UnexpectedEnd
    i usize = 0
    loop {
        if @eq(i, @len(lit)) return @add(offset, @len(lit))
        if @ne(@get(bytes, @add(offset, i)), @get(lit, i)) return ExpectedValue
        i = @add(i, 1)
    }
}

.skip_number(bytes [u8], offset usize) -> usize | JsonError {
    i usize = offset
    if @ge(i, @len(bytes)) return UnexpectedEnd
    if @eq(@get(bytes, i), _minus) {
        i = @add(i, 1)
    }
    if @or(@ge(i, @len(bytes)), @not(is_digit(@get(bytes, i)))) return ExpectedValue
    loop {
        if @ge(i, @len(bytes)) return i
        if @not(is_digit(@get(bytes, i))) break
        i = @add(i, 1)
    }
    if @lt(i, @len(bytes)) {
        if @eq(@get(bytes, i), _dot) {
            i = @add(i, 1)
            if @or(@ge(i, @len(bytes)), @not(is_digit(@get(bytes, i)))) return ExpectedValue
            loop {
                if @ge(i, @len(bytes)) return i
                if @not(is_digit(@get(bytes, i))) break
                i = @add(i, 1)
            }
        }
    }
    if @lt(i, @len(bytes)) {
        if @or(@eq(@get(bytes, i), _lower_e), @eq(@get(bytes, i), _upper_e)) {
            i = @add(i, 1)
            if @lt(i, @len(bytes)) {
                if @or(@eq(@get(bytes, i), _plus), @eq(@get(bytes, i), _minus)) {
                    i = @add(i, 1)
                }
            }
            if @or(@ge(i, @len(bytes)), @not(is_digit(@get(bytes, i)))) return ExpectedValue
            loop {
                if @ge(i, @len(bytes)) return i
                if @not(is_digit(@get(bytes, i))) return i
                i = @add(i, 1)
            }
        }
    }
    return i
}

.skip_array(bytes [u8], offset usize) -> usize | JsonError {
    i usize = skip_ws(bytes, offset)
    if @ge(i, @len(bytes)) return UnexpectedEnd
    if @ne(@get(bytes, i), _open_bracket) return ExpectedValue
    i = skip_ws(bytes, @add(i, 1))
    if @ge(i, @len(bytes)) return UnexpectedEnd
    if @eq(@get(bytes, i), _close_bracket) return @add(i, 1)
    loop {
        next = skip_value(bytes, i)
        if @is(next, JsonError) return next
        i = skip_ws(bytes, next)
        if @ge(i, @len(bytes)) return UnexpectedEnd
        if @eq(@get(bytes, i), _comma) {
            i = skip_ws(bytes, @add(i, 1))
            continue
        }
        if @eq(@get(bytes, i), _close_bracket) return @add(i, 1)
        return ExpectedComma
    }
}

.skip_object(bytes [u8], offset usize) -> usize | JsonError {
    i usize = skip_ws(bytes, offset)
    if @ge(i, @len(bytes)) return UnexpectedEnd
    if @ne(@get(bytes, i), _open_brace) return ExpectedObject
    i = skip_ws(bytes, @add(i, 1))
    if @ge(i, @len(bytes)) return UnexpectedEnd
    if @eq(@get(bytes, i), _close_brace) return @add(i, 1)
    loop {
        name [u8] = .{}
        next usize = i
        status JsonError | nil = nil
        name, next, status = parse_string_token(bytes, i)
        if @is(status, JsonError) return status

        i = skip_ws(bytes, next)
        if @ge(i, @len(bytes)) return UnexpectedEnd
        if @ne(@get(bytes, i), _colon) return ExpectedColon
        i = skip_ws(bytes, @add(i, 1))

        next_value = skip_value(bytes, i)
        if @is(next_value, JsonError) return next_value
        i = skip_ws(bytes, next_value)
        if @ge(i, @len(bytes)) return UnexpectedEnd
        if @eq(@get(bytes, i), _comma) {
            i = skip_ws(bytes, @add(i, 1))
            continue
        }
        if @eq(@get(bytes, i), _close_brace) return @add(i, 1)
        return ExpectedComma
    }
}

.skip_value(bytes [u8], offset usize) -> usize | JsonError {
    i usize = skip_ws(bytes, offset)
    if @ge(i, @len(bytes)) return UnexpectedEnd
    ch u8 = @get(bytes, i)
    if @eq(ch, _quote) {
        value [u8] = .{}
        next usize = i
        status JsonError | nil = nil
        value, next, status = parse_string_token(bytes, i)
        if @is(status, JsonError) return status
        return next
    }
    if @eq(ch, _open_brace) return skip_object(bytes, i)
    if @eq(ch, _open_bracket) return skip_array(bytes, i)
    if @or(@eq(ch, _minus), is_digit(ch)) return skip_number(bytes, i)
    if @eq(ch, 116) return match_literal(bytes, i, "true")
    if @eq(ch, 102) return match_literal(bytes, i, "false")
    if @eq(ch, 110) return match_literal(bytes, i, "null")
    return ExpectedValue
}

.find_field_value_at(bytes [u8], object_offset usize, key_name text) -> usize | JsonError | nil {
    i usize = skip_ws(bytes, object_offset)
    if @ge(i, @len(bytes)) return UnexpectedEnd
    if @ne(@get(bytes, i), _open_brace) return ExpectedObject
    i = skip_ws(bytes, @add(i, 1))
    if @ge(i, @len(bytes)) return UnexpectedEnd
    if @eq(@get(bytes, i), _close_brace) return nil
    loop {
        name [u8] = .{}
        next usize = i
        status JsonError | nil = nil
        name, next, status = parse_string_token(bytes, i)
        if @is(status, JsonError) return status

        i = skip_ws(bytes, next)
        if @ge(i, @len(bytes)) return UnexpectedEnd
        if @ne(@get(bytes, i), _colon) return ExpectedColon
        i = skip_ws(bytes, @add(i, 1))
        if bytes_eq(name, text_bytes(key_name)) return i

        next_value = skip_value(bytes, i)
        if @is(next_value, JsonError) return next_value
        i = skip_ws(bytes, next_value)
        if @ge(i, @len(bytes)) return UnexpectedEnd
        if @eq(@get(bytes, i), _comma) {
            i = skip_ws(bytes, @add(i, 1))
            continue
        }
        if @eq(@get(bytes, i), _close_brace) return nil
        return ExpectedComma
    }
}

.parse_i32_token(bytes [u8], offset usize) -> i32, usize, JsonError | nil {
    i usize = skip_ws(bytes, offset)
    if @ge(i, @len(bytes)) return 0, i, UnexpectedEnd
    negative bool = false
    if @eq(@get(bytes, i), _minus) {
        negative = true
        i = @add(i, 1)
    }
    if @or(@ge(i, @len(bytes)), @not(is_digit(@get(bytes, i)))) return 0, i, ExpectedValue

    value i32 = 0
    loop {
        if @ge(i, @len(bytes)) {
            if negative return @sub(0, value), i, nil
            return value, i, nil
        }
        ch u8 = @get(bytes, i)
        if @not(is_digit(ch)) break
        value = @add(@mul(value, 10), @as(i32, @sub(ch, _zero)))
        i = @add(i, 1)
    }
    if @lt(i, @len(bytes)) {
        if @or(@eq(@get(bytes, i), _dot), @eq(@get(bytes, i), _lower_e), @eq(@get(bytes, i), _upper_e)) return 0, i, ExpectedValue
    }
    if negative return @sub(0, value), i, nil
    return value, i, nil
}

.parse_bool_token(bytes [u8], offset usize) -> bool, usize, JsonError | nil {
    i usize = skip_ws(bytes, offset)
    if @ge(i, @len(bytes)) return false, i, UnexpectedEnd
    if @eq(@get(bytes, i), 116) {
        next = match_literal(bytes, i, "true")
        if @is(next, JsonError) return false, i, next
        return true, next, nil
    }
    if @eq(@get(bytes, i), 102) {
        next = match_literal(bytes, i, "false")
        if @is(next, JsonError) return false, i, next
        return false, next, nil
    }
    return false, i, ExpectedValue
}

.parse_value(seed i32, bytes [u8], offset usize) -> i32 | JsonError {
    value i32 = 0
    next usize = offset
    status JsonError | nil = nil
    value, next, status = parse_i32_token(bytes, offset)
    if @is(status, JsonError) return status
    return value
}

.parse_value(seed u8, bytes [u8], offset usize) -> u8 | JsonError {
    value i32 = 0
    next usize = offset
    status JsonError | nil = nil
    value, next, status = parse_i32_token(bytes, offset)
    if @is(status, JsonError) return status
    if @lt(value, 0) return ExpectedValue
    if @gt(value, 255) return ExpectedValue
    return @as(u8, value)
}

.parse_value(seed bool, bytes [u8], offset usize) -> bool | JsonError {
    value bool = false
    next usize = offset
    status JsonError | nil = nil
    value, next, status = parse_bool_token(bytes, offset)
    if @is(status, JsonError) return status
    return value
}

.parse_value(seed text, bytes [u8], offset usize) -> text | JsonError {
    value [u8] = .{}
    next usize = offset
    status JsonError | nil = nil
    value, next, status = parse_string_token(bytes, offset)
    if @is(status, JsonError) return status
    return value
}

.parse_value(seed [u8], bytes [u8], offset usize) -> [u8] | JsonError {
    value [u8] = .{}
    next usize = offset
    status JsonError | nil = nil
    value, next, status = parse_string_token(bytes, offset)
    if @is(status, JsonError) return status
    return value
}

#T
.parse_value(seed T, bytes [u8], offset usize) -> T | JsonError {
    return parse_object(seed, bytes, offset)
}

#T
.parse_object(seed T, bytes [u8], offset usize) -> T | JsonError {
    end = skip_object(bytes, offset)
    if @is(end, JsonError) return end

    out T = seed
    loop field = fields(T) {
        value_offset = find_field_value_at(bytes, offset, @field_name(field))
        if @is(value_offset, JsonError) return value_offset
        if @eq(value_offset, nil) continue
        parsed = parse_value(@field_get(out, field), bytes, value_offset)
        if @is(parsed, JsonError) return parsed
        out = @field_set(out, field, parsed)
    }
    return out
}

#T
from_json(bytes [u8]) -> T | JsonError {
    seed T = .{}
    out = parse_object(seed, bytes, 0)
    if @is(out, JsonError) return out
    end = skip_object(bytes, 0)
    if @is(end, JsonError) return end
    rest usize = skip_ws(bytes, end)
    if @ne(rest, @len(bytes)) return InvalidJson
    return out
}
