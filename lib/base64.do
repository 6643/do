Text = @/text.do/Text
List = @/list.do/List
list_empty = @/list.do/empty
list_put = @/list.do/put

Base64Error = InvalidLength | InvalidDigit | InvalidPadding

_pad u8 = 61

_std_alphabet Text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
_url_alphabet Text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

Encoding {
    alphabet Text
    padding u8 = _pad
    pad bool = true
}

_std_encoding Encoding = Encoding{alphabet = _std_alphabet, padding = _pad, pad = true}
_raw_std_encoding Encoding = Encoding{alphabet = _std_alphabet, padding = _pad, pad = false}
_url_encoding Encoding = Encoding{alphabet = _url_alphabet, padding = _pad, pad = true}
_raw_url_encoding Encoding = Encoding{alphabet = _url_alphabet, padding = _pad, pad = false}

new(alphabet Text) -> Encoding {
    return Encoding{alphabet = alphabet, padding = _pad, pad = true}
}

with_padding(enc Encoding, padding u8) -> Encoding {
    return Encoding{
        alphabet = get(enc, .alphabet),
        padding = padding,
        pad = get(enc, .pad),
    }
}

without_padding(enc Encoding) -> Encoding {
    return Encoding{
        alphabet = get(enc, .alphabet),
        padding = get(enc, .padding),
        pad = false,
    }
}

encode(data Text) -> Text {
    return encode_with(_std_encoding, data)
}

encode_raw(data Text) -> Text {
    return encode_with(_raw_std_encoding, data)
}

encode_url(data Text) -> Text {
    return encode_with(_url_encoding, data)
}

encode_raw_url(data Text) -> Text {
    return encode_with(_raw_url_encoding, data)
}

encode_with(enc Encoding, data Text) -> Text {
    out List<u8> = list_empty()
    alphabet Text = get(enc, .alphabet)
    pad bool = get(enc, .pad)
    padding u8 = get(enc, .padding)

    i usize = 0
    loop {
        if eq(i, len(data)) return get(out, .items)
        remain usize = sub(len(data), i)
        if ge(remain, 3) {
            b0 u8 = at(data, i)
            b1 u8 = at(data, add(i, 1))
            b2 u8 = at(data, add(i, 2))
            n u32 = add(add(mul(to_u32(b0), 65536), mul(to_u32(b1), 256)), to_u32(b2))
            out = list_put(out, at(alphabet, to_usize(div(n, 262144))))
            out = list_put(out, at(alphabet, to_usize(rem(div(n, 4096), 64))))
            out = list_put(out, at(alphabet, to_usize(rem(div(n, 64), 64))))
            out = list_put(out, at(alphabet, to_usize(rem(n, 64))))
            i = add(i, 3)
            continue
        }
        if eq(remain, 2) {
            b0 u8 = at(data, i)
            b1 u8 = at(data, add(i, 1))
            n u32 = add(mul(to_u32(b0), 65536), mul(to_u32(b1), 256))
            out = list_put(out, at(alphabet, to_usize(div(n, 262144))))
            out = list_put(out, at(alphabet, to_usize(add(mul(rem(b0, 4), 16), div(b1, 16)))))
            out = list_put(out, at(alphabet, to_usize(mul(rem(b1, 16), 4))))
            if pad {
                out = list_put(out, padding)
            }
            i = add(i, 2)
            continue
        }
        b0 u8 = at(data, i)
        out = list_put(out, at(alphabet, to_usize(div(b0, 4))))
        out = list_put(out, at(alphabet, to_usize(mul(rem(b0, 4), 16))))
        if pad {
            out = list_put(out, padding)
            out = list_put(out, padding)
        }
        i = add(i, 1)
    }
}

decode_digit(c u8, alphabet Text) -> u8 | Base64Error {
    i usize = 0
    loop {
        if eq(i, len(alphabet)) return InvalidDigit
        if eq(at(alphabet, i), c) return to_u8(i)
        i = add(i, 1)
    }
}

decode(data Text) -> Text | Base64Error {
    return decode_with(_std_encoding, data)
}

decode_raw(data Text) -> Text | Base64Error {
    return decode_with(_raw_std_encoding, data)
}

decode_url(data Text) -> Text | Base64Error {
    return decode_with(_url_encoding, data)
}

decode_raw_url(data Text) -> Text | Base64Error {
    return decode_with(_raw_url_encoding, data)
}

decode_with(enc Encoding, data Text) -> Text | Base64Error {
    alphabet Text = get(enc, .alphabet)
    pad bool = get(enc, .pad)
    padding u8 = get(enc, .padding)

    if pad {
        if ne(rem(len(data), 4), 0) return InvalidLength
    } else {
        if eq(rem(len(data), 4), 1) return InvalidLength
    }

    out List<u8> = list_empty()
    i usize = 0
    loop {
        if eq(i, len(data)) return get(out, .items)
        remain usize = sub(len(data), i)

        if ge(remain, 4) {
            c0 u8 = at(data, i)
            c1 u8 = at(data, add(i, 1))
            c2 u8 = at(data, add(i, 2))
            c3 u8 = at(data, add(i, 3))

            if eq(c2, padding) {
                if not(pad) return InvalidPadding
                if or(ne(c3, padding), ne(add(i, 4), len(data))) return InvalidPadding
                v0 = decode_digit(c0, alphabet)
                if is(v0, Base64Error) return v0
                v1 = decode_digit(c1, alphabet)
                if is(v1, Base64Error) return v1
                n u32 = add(mul(to_u32(v0), 262144), mul(to_u32(v1), 4096))
                out = list_put(out, to_u8(div(n, 65536)))
                return get(out, .items)
            }

            if eq(c3, padding) {
                if not(pad) return InvalidPadding
                if ne(add(i, 4), len(data)) return InvalidPadding
                v0 = decode_digit(c0, alphabet)
                if is(v0, Base64Error) return v0
                v1 = decode_digit(c1, alphabet)
                if is(v1, Base64Error) return v1
                v2 = decode_digit(c2, alphabet)
                if is(v2, Base64Error) return v2
                n u32 = add(add(mul(to_u32(v0), 262144), mul(to_u32(v1), 4096)), mul(to_u32(v2), 64))
                out = list_put(out, to_u8(div(n, 65536)))
                out = list_put(out, to_u8(rem(div(n, 256), 256)))
                return get(out, .items)
            }

            v0 = decode_digit(c0, alphabet)
            if is(v0, Base64Error) return v0
            v1 = decode_digit(c1, alphabet)
            if is(v1, Base64Error) return v1
            v2 = decode_digit(c2, alphabet)
            if is(v2, Base64Error) return v2
            v3 = decode_digit(c3, alphabet)
            if is(v3, Base64Error) return v3
            n u32 = add(add(add(mul(to_u32(v0), 262144), mul(to_u32(v1), 4096)), mul(to_u32(v2), 64)), to_u32(v3))
            out = list_put(out, to_u8(div(n, 65536)))
            out = list_put(out, to_u8(rem(div(n, 256), 256)))
            out = list_put(out, to_u8(rem(n, 256)))
            i = add(i, 4)
            continue
        }

        if pad return InvalidLength
        if eq(remain, 2) {
            c0 u8 = at(data, i)
            c1 u8 = at(data, add(i, 1))
            v0 = decode_digit(c0, alphabet)
            if is(v0, Base64Error) return v0
            v1 = decode_digit(c1, alphabet)
            if is(v1, Base64Error) return v1
            n u32 = add(mul(to_u32(v0), 262144), mul(to_u32(v1), 4096))
            out = list_put(out, to_u8(div(n, 65536)))
            return get(out, .items)
        }

        if eq(remain, 3) {
            c0 u8 = at(data, i)
            c1 u8 = at(data, add(i, 1))
            c2 u8 = at(data, add(i, 2))
            v0 = decode_digit(c0, alphabet)
            if is(v0, Base64Error) return v0
            v1 = decode_digit(c1, alphabet)
            if is(v1, Base64Error) return v1
            v2 = decode_digit(c2, alphabet)
            if is(v2, Base64Error) return v2
            n u32 = add(add(mul(to_u32(v0), 262144), mul(to_u32(v1), 4096)), mul(to_u32(v2), 64))
            out = list_put(out, to_u8(div(n, 65536)))
            out = list_put(out, to_u8(rem(div(n, 256), 256)))
            return get(out, .items)
        }

        return InvalidLength
    }
}
