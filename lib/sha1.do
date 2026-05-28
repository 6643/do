Text = @/text.do/Text
List = @/list.do/List
list_put = @/list.do/put
list_len = @/list.do/len
list_items = @/list.do/items
read_u32_be = @/binary.do/read_u32_be

_sha1_h0 u32 = 1732584193
_sha1_h1 u32 = 4023233417
_sha1_h2 u32 = 2562383102
_sha1_h3 u32 = 271733878
_sha1_h4 u32 = 3285377520
_sha1_k0 u32 = 1518500249
_sha1_k1 u32 = 1859775393
_sha1_k2 u32 = 2400959708
_sha1_k3 u32 = 3395469782

sha1_f0(b u32, c u32, d u32) -> u32 {
    return bit_or_u32(bit_and_u32(b, c), bit_and_u32(bit_not_u32(b), d))
}

sha1_f1(b u32, c u32, d u32) -> u32 {
    return bit_xor_u32(bit_xor_u32(b, c), d)
}

sha1_f2(b u32, c u32, d u32) -> u32 {
    return bit_or_u32(bit_or_u32(bit_and_u32(b, c), bit_and_u32(b, d)), bit_and_u32(c, d))
}

sha1_f3(b u32, c u32, d u32) -> u32 {
    return bit_xor_u32(bit_xor_u32(b, c), d)
}

_append_u64_be(out List<u8>, value u64) -> List<u8> {
    out = list_put(out, to_u8(rem(div(value, 72057594037927936), 256)))
    out = list_put(out, to_u8(rem(div(value, 281474976710656), 256)))
    out = list_put(out, to_u8(rem(div(value, 1099511627776), 256)))
    out = list_put(out, to_u8(rem(div(value, 4294967296), 256)))
    out = list_put(out, to_u8(rem(div(value, 16777216), 256)))
    out = list_put(out, to_u8(rem(div(value, 65536), 256)))
    out = list_put(out, to_u8(rem(div(value, 256), 256)))
    out = list_put(out, to_u8(rem(value, 256)))
    return out
}

_append_u32_be(out List<u8>, value u32) -> List<u8> {
    out = list_put(out, to_u8(rem(div(value, 16777216), 256)))
    out = list_put(out, to_u8(rem(div(value, 65536), 256)))
    out = list_put(out, to_u8(rem(div(value, 256), 256)))
    out = list_put(out, to_u8(rem(value, 256)))
    return out
}

_pad(text Text) -> List<u8> {
    out List<u8> = List<u8>{}
    loop b, _ = text {
        out = list_put(out, b)
    }
    out = list_put(out, 128)
    loop {
        if eq(rem(list_len(out), 64), 56) return _append_u64_be(out, mul(to_u64(len(text)), 8))
        out = list_put(out, 0)
    }
}

_block(h0 u32, h1 u32, h2 u32, h3 u32, h4 u32, block List<u8>, base usize) -> u32, u32, u32, u32, u32 {
    items [u8] = list_items(block)
    w [u32] = .{}
    w = put(w, read_u32_be(items, base))
    w = put(w, read_u32_be(items, add(base, 4)))
    w = put(w, read_u32_be(items, add(base, 8)))
    w = put(w, read_u32_be(items, add(base, 12)))
    w = put(w, read_u32_be(items, add(base, 16)))
    w = put(w, read_u32_be(items, add(base, 20)))
    w = put(w, read_u32_be(items, add(base, 24)))
    w = put(w, read_u32_be(items, add(base, 28)))
    w = put(w, read_u32_be(items, add(base, 32)))
    w = put(w, read_u32_be(items, add(base, 36)))
    w = put(w, read_u32_be(items, add(base, 40)))
    w = put(w, read_u32_be(items, add(base, 44)))
    w = put(w, read_u32_be(items, add(base, 48)))
    w = put(w, read_u32_be(items, add(base, 52)))
    w = put(w, read_u32_be(items, add(base, 56)))
    w = put(w, read_u32_be(items, add(base, 60)))

    a u32 = h0
    b u32 = h1
    c u32 = h2
    d u32 = h3
    e u32 = h4

    i usize = 0
    loop {
        if eq(i, 80) {
            return add_wrap_u32(h0, a), add_wrap_u32(h1, b), add_wrap_u32(h2, c), add_wrap_u32(h3, d), add_wrap_u32(h4, e)
        }

        idx usize = rem(i, 16)
        if ge(i, 16) {
            s u32 = bit_xor_u32(
                bit_xor_u32(at(w, rem(sub(i, 3), 16)), at(w, rem(sub(i, 8), 16))),
                bit_xor_u32(at(w, rem(sub(i, 14), 16)), at(w, idx)),
            )
            w = set(w, idx, rotl_u32(s, 1))
        }

        wi u32 = at(w, idx)
        f u32 = sha1_f1(b, c, d)
        k u32 = _sha1_k3
        if lt(i, 20) {
            f = sha1_f0(b, c, d)
            k = _sha1_k0
        } else if lt(i, 40) {
            k = _sha1_k1
        } else if lt(i, 60) {
            f = sha1_f2(b, c, d)
            k = _sha1_k2
        } else {
            f = sha1_f3(b, c, d)
        }

        t u32 = add_wrap_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(rotl_u32(a, 5), f), e), wi), k)
        e = d
        d = c
        c = rotl_u32(b, 30)
        b = a
        a = t
        i = add(i, 1)
    }
}

sum(text Text) -> Text {
    padded List<u8> = _pad(text)
    a u32 = _sha1_h0
    b u32 = _sha1_h1
    c u32 = _sha1_h2
    d u32 = _sha1_h3
    e u32 = _sha1_h4

    i usize = 0
    loop {
        if ge(i, list_len(padded)) {
            out List<u8> = List<u8>{}
            out = _append_u32_be(out, a)
            out = _append_u32_be(out, b)
            out = _append_u32_be(out, c)
            out = _append_u32_be(out, d)
            out = _append_u32_be(out, e)
            return get(out, .items)
        }
        a, b, c, d, e = _block(a, b, c, d, e, padded, i)
        i = add(i, 64)
    }
}
