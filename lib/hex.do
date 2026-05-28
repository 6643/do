Text = @/text.do/Text
List = @/list.do/List
list_put = @/list.do/put
list_len = @/list.do/len
list_items = @/list.do/items

HexError = InvalidLength | InvalidDigit

_hex_0 u8 = 48
_hex_9 u8 = 57
_hex_A u8 = 65
_hex_F u8 = 70
_hex_a u8 = 97
_hex_f u8 = 102

_lower_alphabet Text = "0123456789abcdef"
_upper_alphabet Text = "0123456789ABCDEF"

encode(data Text) -> Text {
    return encode_with(data, _lower_alphabet)
}

encode_upper(data Text) -> Text {
    return encode_with(data, _upper_alphabet)
}

encode_with(data Text, alphabet Text) -> Text {
    out List<u8> = List<u8>{}
    i usize = 0
    loop {
        if eq(i, len(data)) return get(out, .items)
        b u8 = at(data, i)
        hi u8 = to_u8(div(b, 16))
        lo u8 = to_u8(rem(b, 16))
        out = list_put(out, at(alphabet, to_usize(hi)))
        out = list_put(out, at(alphabet, to_usize(lo)))
        i = add(i, 1)
    }
}

decode_digit(c u8) -> u8 | HexError {
    if and(ge(c, _hex_0), le(c, _hex_9)) return sub(c, _hex_0)
    if and(ge(c, _hex_a), le(c, _hex_f)) return add(sub(c, _hex_a), 10)
    if and(ge(c, _hex_A), le(c, _hex_F)) return add(sub(c, _hex_A), 10)
    return InvalidDigit
}

decode(text Text) -> Text | HexError {
    if ne(rem(len(text), 2), 0) return InvalidLength
    out List<u8> = List<u8>{}
    i usize = 0
    loop {
        if eq(i, len(text)) return get(out, .items)
        hi = decode_digit(at(text, i))
        if is(hi, HexError) return hi
        lo = decode_digit(at(text, add(i, 1)))
        if is(lo, HexError) return lo
        out = list_put(out, add(mul(hi, 16), lo))
        i = add(i, 2)
    }
}
