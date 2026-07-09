List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_add = @lib("list.do", list_add)
list_items = @lib("list.do", items)

Base64Error error = InvalidLength | InvalidDigit | InvalidPadding

_pad u8 = 61
_base64_upper_a u8 = 65
_base64_lower_a u8 = 97
_base64_0 u8 = 48
_base64_std_62 u8 = 43
_base64_std_63 u8 = 47
_base64_url_62 u8 = 45
_base64_url_63 u8 = 95

_std_alphabet [u8] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
_url_alphabet [u8] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

Encoding {
    alphabet [u8]
    padding u8 = _pad
    pad bool = true
}

_std_encoding Encoding = Encoding{alphabet = _std_alphabet, padding = _pad, pad = true}
_raw_std_encoding Encoding = Encoding{alphabet = _std_alphabet, padding = _pad, pad = false}
_url_encoding Encoding = Encoding{alphabet = _url_alphabet, padding = _pad, pad = true}
_raw_url_encoding Encoding = Encoding{alphabet = _url_alphabet, padding = _pad, pad = false}

new(alphabet [u8]) -> Encoding {
    return Encoding{alphabet = alphabet, padding = _pad, pad = true}
}

with_padding(enc Encoding, padding u8) -> Encoding {
    return Encoding{alphabet = @get(enc, .alphabet), padding = padding, pad = @get(enc, .pad)}
}

without_padding(enc Encoding) -> Encoding {
    return Encoding{alphabet = @get(enc, .alphabet), padding = @get(enc, .padding), pad = false}
}

encode(data [u8]) -> [u8] {
    return encode_config(data, true, false)
}

encode_raw(data [u8]) -> [u8] {
    return encode_config(data, false, false)
}

encode_url(data [u8]) -> [u8] {
    return encode_config(data, true, true)
}

encode_raw_url(data [u8]) -> [u8] {
    return encode_config(data, false, true)
}

encode_digit(index u8, url bool) -> u8 {
    if @le(index, 25) return @add(_base64_upper_a, index)
    if @le(index, 51) return @add(_base64_lower_a, @sub(index, 26))
    if @le(index, 61) return @add(_base64_0, @sub(index, 52))
    if @eq(index, 62) {
        if url return _base64_url_62
        return _base64_std_62
    }
    if url return _base64_url_63
    return _base64_std_63
}

encode_config(data [u8], pad bool, url bool) -> [u8] {
    out [u8] = .{}
    i usize = 0
    loop {
        if @eq(i, @len(data)) return out
        remain usize = @sub(@len(data), i)
        if @ge(remain, 3) {
            b0_full u8 = @get(data, i)
            b1_full u8 = @get(data, @add(i, 1))
            b2_full u8 = @get(data, @add(i, 2))
            n_full u32 = @add(@mul(@as(u32, b0_full), 65536), @mul(@as(u32, b1_full), 256), @as(u32, b2_full))
            out = @put(out, encode_digit(@as(u8, @div(n_full, 262144)), url))
            out = @put(out, encode_digit(@as(u8, @rem(@div(n_full, 4096), 64)), url))
            out = @put(out, encode_digit(@as(u8, @rem(@div(n_full, 64), 64)), url))
            out = @put(out, encode_digit(@as(u8, @rem(n_full, 64)), url))
            i = @add(i, 3)
            continue
        }
        if @eq(remain, 2) {
            b0_tail2 u8 = @get(data, i)
            b1_tail2 u8 = @get(data, @add(i, 1))
            n_tail2 u32 = @add(@mul(@as(u32, b0_tail2), 65536), @mul(@as(u32, b1_tail2), 256))
            out = @put(out, encode_digit(@as(u8, @div(n_tail2, 262144)), url))
            out = @put(out, encode_digit(@as(u8, @rem(@div(n_tail2, 4096), 64)), url))
            out = @put(out, encode_digit(@as(u8, @rem(@div(n_tail2, 64), 64)), url))
            if pad {
                out = @put(out, _pad)
            }
            i = @add(i, 2)
            continue
        }
        b0_tail1 u8 = @get(data, i)
        out = @put(out, encode_digit(@div(b0_tail1, 4), url))
        out = @put(out, encode_digit(@mul(@rem(b0_tail1, 4), 16), url))
        if pad {
            out = @put(out, _pad)
            out = @put(out, _pad)
        }
        i = @add(i, 1)
    }
}

encode_with(enc Encoding, data [u8]) -> [u8] {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    alphabet [u8] = @get(enc, .alphabet)
    pad bool = @get(enc, .pad)
    padding u8 = @get(enc, .padding)

    i usize = 0
    loop {
        if @eq(i, @len(data)) return list_items(out)
        remain usize = @sub(@len(data), i)
        if @ge(remain, 3) {
            b0 u8 = @get(data, i)
            b1 u8 = @get(data, @add(i, 1))
            b2 u8 = @get(data, @add(i, 2))
            n u32 = @add(@mul(@as(u32, b0), 65536), @mul(@as(u32, b1), 256), @as(u32, b2))
            out = list_add(out, @get(alphabet, @as(usize, @div(n, 262144))))
            out = list_add(out, @get(alphabet, @as(usize, @rem(@div(n, 4096), 64))))
            out = list_add(out, @get(alphabet, @as(usize, @rem(@div(n, 64), 64))))
            out = list_add(out, @get(alphabet, @as(usize, @rem(n, 64))))
            i = @add(i, 3)
            continue
        }
        if @eq(remain, 2) {
            b0 u8 = @get(data, i)
            b1 u8 = @get(data, @add(i, 1))
            n u32 = @add(@mul(@as(u32, b0), 65536), @mul(@as(u32, b1), 256))
            out = list_add(out, @get(alphabet, @as(usize, @div(n, 262144))))
            out = list_add(out, @get(alphabet, @as(usize, @add(@mul(@rem(b0, 4), 16), @div(b1, 16)))))
            out = list_add(out, @get(alphabet, @as(usize, @mul(@rem(b1, 16), 4))))
            if pad {
                out = list_add(out, padding)
            }
            i = @add(i, 2)
            continue
        }
        b0 u8 = @get(data, i)
        out = list_add(out, @get(alphabet, @as(usize, @div(b0, 4))))
        out = list_add(out, @get(alphabet, @as(usize, @mul(@rem(b0, 4), 16))))
        if pad {
            out = list_add(out, padding)
            out = list_add(out, padding)
        }
        i = @add(i, 1)
    }
}

decode_digit(c u8, alphabet [u8]) -> u8 | Base64Error {
    i usize = 0
    loop {
        if @eq(i, @len(alphabet)) return InvalidDigit
        if @eq(@get(alphabet, i), c) return @as(u8, i)
        i = @add(i, 1)
    }
}

decode(data [u8]) -> [u8] | Base64Error {
    return decode_config(data, true, false)
}

decode_raw(data [u8]) -> [u8] | Base64Error {
    return decode_config(data, false, false)
}

decode_url(data [u8]) -> [u8] | Base64Error {
    return decode_config(data, true, true)
}

decode_raw_url(data [u8]) -> [u8] | Base64Error {
    return decode_config(data, false, true)
}

decode_digit_config(c u8, url bool) -> u8 | Base64Error {
    if @and(@ge(c, _base64_upper_a), @le(c, @add(_base64_upper_a, 25))) return @sub(c, _base64_upper_a)
    if @and(@ge(c, _base64_lower_a), @le(c, @add(_base64_lower_a, 25))) return @add(@sub(c, _base64_lower_a), 26)
    if @and(@ge(c, _base64_0), @le(c, @add(_base64_0, 9))) return @add(@sub(c, _base64_0), 52)
    if url {
        if @eq(c, _base64_url_62) return 62
        if @eq(c, _base64_url_63) return 63
        return InvalidDigit
    }
    if @eq(c, _base64_std_62) return 62
    if @eq(c, _base64_std_63) return 63
    return InvalidDigit
}

decode_config(data [u8], pad bool, url bool) -> [u8] | Base64Error {
    if pad {
        if @ne(@rem(@len(data), 4), 0) return InvalidLength
    } else {
        if @eq(@rem(@len(data), 4), 1) return InvalidLength
    }

    out [u8] = .{}
    i usize = 0
    loop {
        if @eq(i, @len(data)) return out
        remain usize = @sub(@len(data), i)

        if @ge(remain, 4) {
            c0_full u8 = @get(data, i)
            c1_full u8 = @get(data, @add(i, 1))
            c2_full u8 = @get(data, @add(i, 2))
            c3_full u8 = @get(data, @add(i, 3))

            if @eq(c2_full, _pad) {
                if @not(pad) return InvalidPadding
                if @or(@ne(c3_full, _pad), @ne(@add(i, 4), @len(data))) return InvalidPadding
                v0_pad2 = decode_digit_config(c0_full, url)
                if @is(v0_pad2, Base64Error) return v0_pad2
                v1_pad2 = decode_digit_config(c1_full, url)
                if @is(v1_pad2, Base64Error) return v1_pad2
                n_pad2 u32 = @add(@mul(@as(u32, v0_pad2), 262144), @mul(@as(u32, v1_pad2), 4096))
                out = @put(out, @as(u8, @div(n_pad2, 65536)))
                return out
            }

            if @eq(c3_full, _pad) {
                if @not(pad) return InvalidPadding
                if @ne(@add(i, 4), @len(data)) return InvalidPadding
                v0_pad1 = decode_digit_config(c0_full, url)
                if @is(v0_pad1, Base64Error) return v0_pad1
                v1_pad1 = decode_digit_config(c1_full, url)
                if @is(v1_pad1, Base64Error) return v1_pad1
                v2_pad1 = decode_digit_config(c2_full, url)
                if @is(v2_pad1, Base64Error) return v2_pad1
                n_pad1 u32 = @add(@mul(@as(u32, v0_pad1), 262144), @mul(@as(u32, v1_pad1), 4096), @mul(@as(u32, v2_pad1), 64))
                out = @put(out, @as(u8, @div(n_pad1, 65536)))
                out = @put(out, @as(u8, @rem(@div(n_pad1, 256), 256)))
                return out
            }

            v0_full = decode_digit_config(c0_full, url)
            if @is(v0_full, Base64Error) return v0_full
            v1_full = decode_digit_config(c1_full, url)
            if @is(v1_full, Base64Error) return v1_full
            v2_full = decode_digit_config(c2_full, url)
            if @is(v2_full, Base64Error) return v2_full
            v3_full = decode_digit_config(c3_full, url)
            if @is(v3_full, Base64Error) return v3_full
            n_full_dec u32 = @add(@mul(@as(u32, v0_full), 262144), @mul(@as(u32, v1_full), 4096), @mul(@as(u32, v2_full), 64), @as(u32, v3_full))
            out = @put(out, @as(u8, @div(n_full_dec, 65536)))
            out = @put(out, @as(u8, @rem(@div(n_full_dec, 256), 256)))
            out = @put(out, @as(u8, @rem(n_full_dec, 256)))
            i = @add(i, 4)
            continue
        }

        if pad return InvalidLength
        if @eq(remain, 2) {
            c0_tail2 u8 = @get(data, i)
            c1_tail2 u8 = @get(data, @add(i, 1))
            v0_tail2 = decode_digit_config(c0_tail2, url)
            if @is(v0_tail2, Base64Error) return v0_tail2
            v1_tail2 = decode_digit_config(c1_tail2, url)
            if @is(v1_tail2, Base64Error) return v1_tail2
            n_tail2_dec u32 = @add(@mul(@as(u32, v0_tail2), 262144), @mul(@as(u32, v1_tail2), 4096))
            out = @put(out, @as(u8, @div(n_tail2_dec, 65536)))
            return out
        }

        if @eq(remain, 3) {
            c0_tail3 u8 = @get(data, i)
            c1_tail3 u8 = @get(data, @add(i, 1))
            c2_tail3 u8 = @get(data, @add(i, 2))
            v0_tail3 = decode_digit_config(c0_tail3, url)
            if @is(v0_tail3, Base64Error) return v0_tail3
            v1_tail3 = decode_digit_config(c1_tail3, url)
            if @is(v1_tail3, Base64Error) return v1_tail3
            v2_tail3 = decode_digit_config(c2_tail3, url)
            if @is(v2_tail3, Base64Error) return v2_tail3
            n_tail3_dec u32 = @add(@mul(@as(u32, v0_tail3), 262144), @mul(@as(u32, v1_tail3), 4096), @mul(@as(u32, v2_tail3), 64))
            out = @put(out, @as(u8, @div(n_tail3_dec, 65536)))
            out = @put(out, @as(u8, @rem(@div(n_tail3_dec, 256), 256)))
            return out
        }

        return InvalidLength
    }
}

decode_with(enc Encoding, data [u8]) -> [u8] | Base64Error {
    alphabet [u8] = @get(enc, .alphabet)
    pad bool = @get(enc, .pad)
    padding u8 = @get(enc, .padding)

    if pad {
        if @ne(@rem(@len(data), 4), 0) return InvalidLength
    } else {
        if @eq(@rem(@len(data), 4), 1) return InvalidLength
    }

    seed u8 = 0
    out List<u8> = empty_list(seed)
    i usize = 0
    loop {
        if @eq(i, @len(data)) return list_items(out)
        remain usize = @sub(@len(data), i)

        if @ge(remain, 4) {
            c0 u8 = @get(data, i)
            c1 u8 = @get(data, @add(i, 1))
            c2 u8 = @get(data, @add(i, 2))
            c3 u8 = @get(data, @add(i, 3))

            if @eq(c2, padding) {
                if @not(pad) return InvalidPadding
                if @or(@ne(c3, padding), @ne(@add(i, 4), @len(data))) return InvalidPadding
                v0 = decode_digit(c0, alphabet)
                if @is(v0, Base64Error) return v0
                v1 = decode_digit(c1, alphabet)
                if @is(v1, Base64Error) return v1
                n u32 = @add(@mul(@as(u32, v0), 262144), @mul(@as(u32, v1), 4096))
                out = list_add(out, @as(u8, @div(n, 65536)))
                return list_items(out)
            }

            if @eq(c3, padding) {
                if @not(pad) return InvalidPadding
                if @ne(@add(i, 4), @len(data)) return InvalidPadding
                v0 = decode_digit(c0, alphabet)
                if @is(v0, Base64Error) return v0
                v1 = decode_digit(c1, alphabet)
                if @is(v1, Base64Error) return v1
                v2 = decode_digit(c2, alphabet)
                if @is(v2, Base64Error) return v2
                n u32 = @add(@mul(@as(u32, v0), 262144), @mul(@as(u32, v1), 4096), @mul(@as(u32, v2), 64))
                out = list_add(out, @as(u8, @div(n, 65536)))
                out = list_add(out, @as(u8, @rem(@div(n, 256), 256)))
                return list_items(out)
            }

            v0 = decode_digit(c0, alphabet)
            if @is(v0, Base64Error) return v0
            v1 = decode_digit(c1, alphabet)
            if @is(v1, Base64Error) return v1
            v2 = decode_digit(c2, alphabet)
            if @is(v2, Base64Error) return v2
            v3 = decode_digit(c3, alphabet)
            if @is(v3, Base64Error) return v3
            n u32 = @add(@mul(@as(u32, v0), 262144), @mul(@as(u32, v1), 4096), @mul(@as(u32, v2), 64), @as(u32, v3))
            out = list_add(out, @as(u8, @div(n, 65536)))
            out = list_add(out, @as(u8, @rem(@div(n, 256), 256)))
            out = list_add(out, @as(u8, @rem(n, 256)))
            i = @add(i, 4)
            continue
        }

        if pad return InvalidLength
        if @eq(remain, 2) {
            c0 u8 = @get(data, i)
            c1 u8 = @get(data, @add(i, 1))
            v0 = decode_digit(c0, alphabet)
            if @is(v0, Base64Error) return v0
            v1 = decode_digit(c1, alphabet)
            if @is(v1, Base64Error) return v1
            n u32 = @add(@mul(@as(u32, v0), 262144), @mul(@as(u32, v1), 4096))
            out = list_add(out, @as(u8, @div(n, 65536)))
            return list_items(out)
        }

        if @eq(remain, 3) {
            c0 u8 = @get(data, i)
            c1 u8 = @get(data, @add(i, 1))
            c2 u8 = @get(data, @add(i, 2))
            v0 = decode_digit(c0, alphabet)
            if @is(v0, Base64Error) return v0
            v1 = decode_digit(c1, alphabet)
            if @is(v1, Base64Error) return v1
            v2 = decode_digit(c2, alphabet)
            if @is(v2, Base64Error) return v2
            n u32 = @add(@mul(@as(u32, v0), 262144), @mul(@as(u32, v1), 4096), @mul(@as(u32, v2), 64))
            out = list_add(out, @as(u8, @div(n, 65536)))
            out = list_add(out, @as(u8, @rem(@div(n, 256), 256)))
            return list_items(out)
        }

        return InvalidLength
    }
}
