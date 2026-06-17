List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_add = @lib("list.do", list_add)
list_len = @lib("list.do", list_len)
list_items = @lib("list.do", items)

HexError error = InvalidLength | InvalidDigit

_hex_0 u8 = 48
_hex_9 u8 = 57
_hex_upper_a u8 = 65
_hex_upper_f u8 = 70
_hex_a u8 = 97
_hex_f u8 = 102

_lower_alphabet [u8] = "0123456789abcdef"
_upper_alphabet [u8] = "0123456789ABCDEF"

encode(data [u8]) -> [u8] {
    return encode_with(data, _lower_alphabet)
}

encode_upper(data [u8]) -> [u8] {
    return encode_with(data, _upper_alphabet)
}

encode_with(data [u8], alphabet [u8]) -> [u8] {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    i usize = 0
    loop {
        if @eq(i, @len(data)) return list_items(out)
        b u8 = @get(data, i)
        hi u8 = @as(u8, @div(b, 16))
        lo u8 = @as(u8, @rem(b, 16))
        out = list_add(out, @get(alphabet, @as(usize, hi)))
        out = list_add(out, @get(alphabet, @as(usize, lo)))
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
    seed u8 = 0
    out List<u8> = empty_list(seed)
    i usize = 0
    loop {
        if @eq(i, @len(bytes)) return list_items(out)
        hi = decode_digit(@get(bytes, i))
        if @is(hi, HexError) return hi
        lo = decode_digit(@get(bytes, @add(i, 1)))
        if @is(lo, HexError) return lo
        out = list_add(out, @add(@mul(hi, 16), lo))
        i = @add(i, 2)
    }
}
