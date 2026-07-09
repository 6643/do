HexError error = InvalidLength | InvalidDigit

_hex_0 u8 = 48
_hex_9 u8 = 57
_hex_upper_a u8 = 65
_hex_upper_f u8 = 70
_hex_a u8 = 97
_hex_f u8 = 102

encode(data [u8]) -> [u8] {
    return encode_with(data, false)
}

encode_upper(data [u8]) -> [u8] {
    return encode_with(data, true)
}

encode_digit(value u8, upper bool) -> u8 {
    if @le(value, 9) return @add(_hex_0, value)
    if upper return @add(_hex_upper_a, @sub(value, 10))
    return @add(_hex_a, @sub(value, 10))
}

encode_with(data [u8], upper bool) -> [u8] {
    out [u8] = .{}
    i usize = 0
    loop {
        if @eq(i, @len(data)) return out
        b u8 = @get(data, i)
        hi u8 = @as(u8, @div(b, 16))
        lo u8 = @as(u8, @rem(b, 16))
        out = @put(out, encode_digit(hi, upper))
        out = @put(out, encode_digit(lo, upper))
        i = @add(i, 1)
    }
}

decode_digit(c u8) -> u8 | HexError {
    if @and(@ge(c, _hex_0), @le(c, _hex_9)) return @sub(c, _hex_0)
    if @and(@ge(c, _hex_a), @le(c, _hex_f)) return @add(@sub(c, _hex_a), 10)
    if @and(@ge(c, _hex_upper_a), @le(c, _hex_upper_f)) return @add(@sub(c, _hex_upper_a), 10)
    return InvalidDigit
}

decode(bytes [u8]) -> [u8] | HexError {
    if @ne(@rem(@len(bytes), 2), 0) return InvalidLength
    out [u8] = .{}
    i usize = 0
    loop {
        if @eq(i, @len(bytes)) return out
        hi = decode_digit(@get(bytes, i))
        if @is(hi, HexError) return hi
        lo = decode_digit(@get(bytes, @add(i, 1)))
        if @is(lo, HexError) return lo
        out = @put(out, @add(@mul(hi, 16), lo))
        i = @add(i, 2)
    }
}
