Text = @/text.do/Text
List = @/list.do/List
list_empty = @/list.do/empty
list_put = @/list.do/put
list_len = @/list.do/len
list_items = @/list.do/items
read_u32_be = @/binary.do/read_u32_be

_sha256_h0 u32 = 1779033703
_sha256_h1 u32 = 3144134277
_sha256_h2 u32 = 1013904242
_sha256_h3 u32 = 2773480762
_sha256_h4 u32 = 1359893119
_sha256_h5 u32 = 2600822924
_sha256_h6 u32 = 528734635
_sha256_h7 u32 = 1541459225

sha256_ch(x u32, y u32, z u32) -> u32 {
    return bit_or_u32(bit_and_u32(x, y), bit_and_u32(bit_not_u32(x), z))
}

sha256_maj(x u32, y u32, z u32) -> u32 {
    return bit_or_u32(bit_or_u32(bit_and_u32(x, y), bit_and_u32(x, z)), bit_and_u32(y, z))
}

sha256_big_sigma0(x u32) -> u32 {
    return bit_xor_u32(bit_xor_u32(rotr_u32(x, 2), rotr_u32(x, 13)), rotr_u32(x, 22))
}

sha256_big_sigma1(x u32) -> u32 {
    return bit_xor_u32(bit_xor_u32(rotr_u32(x, 6), rotr_u32(x, 11)), rotr_u32(x, 25))
}

sha256_small_sigma0(x u32) -> u32 {
    return bit_xor_u32(bit_xor_u32(rotr_u32(x, 7), rotr_u32(x, 18)), shr_u32(x, 3))
}

sha256_small_sigma1(x u32) -> u32 {
    return bit_xor_u32(bit_xor_u32(rotr_u32(x, 17), rotr_u32(x, 19)), shr_u32(x, 10))
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

_sha256_k_table() -> [u32] {
    out [u32] = storage()
    out = put(out, 1116352408)
    out = put(out, 1899447441)
    out = put(out, 3049323471)
    out = put(out, 3921009573)
    out = put(out, 961987163)
    out = put(out, 1508970993)
    out = put(out, 2453635748)
    out = put(out, 2870763221)
    out = put(out, 3624381080)
    out = put(out, 310598401)
    out = put(out, 607225278)
    out = put(out, 1426881987)
    out = put(out, 1925078388)
    out = put(out, 2162078206)
    out = put(out, 2614888103)
    out = put(out, 3248222580)
    out = put(out, 3835390401)
    out = put(out, 4022224774)
    out = put(out, 264347078)
    out = put(out, 604807628)
    out = put(out, 770255983)
    out = put(out, 1249150122)
    out = put(out, 1555081692)
    out = put(out, 1996064986)
    out = put(out, 2554220882)
    out = put(out, 2821834349)
    out = put(out, 2952996808)
    out = put(out, 3210313671)
    out = put(out, 3336571891)
    out = put(out, 3584528711)
    out = put(out, 113926993)
    out = put(out, 338241895)
    out = put(out, 666307205)
    out = put(out, 773529912)
    out = put(out, 1294757372)
    out = put(out, 1396182291)
    out = put(out, 1695183700)
    out = put(out, 1986661051)
    out = put(out, 2177026350)
    out = put(out, 2456956037)
    out = put(out, 2730485921)
    out = put(out, 2820302411)
    out = put(out, 3259730800)
    out = put(out, 3345764771)
    out = put(out, 3516065817)
    out = put(out, 3600352804)
    out = put(out, 4094571909)
    out = put(out, 275423344)
    out = put(out, 430227734)
    out = put(out, 506948616)
    out = put(out, 659060556)
    out = put(out, 883997877)
    out = put(out, 958139571)
    out = put(out, 1322822218)
    out = put(out, 1537002063)
    out = put(out, 1747873779)
    out = put(out, 1955562222)
    out = put(out, 2024104815)
    out = put(out, 2227730452)
    out = put(out, 2361852424)
    out = put(out, 2428436474)
    out = put(out, 2756734187)
    out = put(out, 3204031479)
    out = put(out, 3329325298)
    return out
}

_sha256_k [u32] = _sha256_k_table()

_pad(text Text) -> List<u8> {
    out List<u8> = list_empty()
    loop b, _ = text {
        out = list_put(out, b)
    }
    out = list_put(out, 128)
    loop {
        if eq(rem(list_len(out), 64), 56) return _append_u64_be(out, mul(to_u64(len(text)), 8))
        out = list_put(out, 0)
    }
}

_block(h0 u32, h1 u32, h2 u32, h3 u32, h4 u32, h5 u32, h6 u32, h7 u32, block List<u8>, base usize) -> u32, u32, u32, u32, u32, u32, u32, u32 {
    items [u8] = list_items(block)
    w [u32] = storage()
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
    f u32 = h5
    g u32 = h6
    h u32 = h7

    i usize = 0
    loop {
        if eq(i, 64) {
            return add_wrap_u32(h0, a), add_wrap_u32(h1, b), add_wrap_u32(h2, c), add_wrap_u32(h3, d), add_wrap_u32(h4, e), add_wrap_u32(h5, f), add_wrap_u32(h6, g), add_wrap_u32(h7, h)
        }

        idx usize = rem(i, 16)
        if ge(i, 16) {
            s0 u32 = sha256_small_sigma0(at(w, rem(sub(i, 15), 16)))
            s1 u32 = sha256_small_sigma1(at(w, rem(sub(i, 2), 16)))
            next u32 = add_wrap_u32(
                add_wrap_u32(
                    add_wrap_u32(s1, at(w, rem(sub(i, 7), 16))),
                    s0,
                ),
                at(w, idx),
            )
            w = set(w, idx, next)
        }

        wi u32 = at(w, idx)
        t1 u32 = add_wrap_u32(
            add_wrap_u32(
                add_wrap_u32(
                    add_wrap_u32(h, sha256_big_sigma1(e)),
                    sha256_ch(e, f, g),
                ),
                at(_sha256_k, i),
            ),
            wi,
        )
        t2 u32 = add_wrap_u32(sha256_big_sigma0(a), sha256_maj(a, b, c))

        h = g
        g = f
        f = e
        e = add_wrap_u32(d, t1)
        d = c
        c = b
        b = a
        a = add_wrap_u32(t1, t2)
        i = add(i, 1)
    }
}

sum(text Text) -> Text {
    padded List<u8> = _pad(text)
    a u32 = _sha256_h0
    b u32 = _sha256_h1
    c u32 = _sha256_h2
    d u32 = _sha256_h3
    e u32 = _sha256_h4
    f u32 = _sha256_h5
    g u32 = _sha256_h6
    h u32 = _sha256_h7

    i usize = 0
    loop {
        if ge(i, list_len(padded)) {
            out List<u8> = list_empty()
            out = _append_u32_be(out, a)
            out = _append_u32_be(out, b)
            out = _append_u32_be(out, c)
            out = _append_u32_be(out, d)
            out = _append_u32_be(out, e)
            out = _append_u32_be(out, f)
            out = _append_u32_be(out, g)
            out = _append_u32_be(out, h)
            return get(out, .items)
        }
        a, b, c, d, e, f, g, h = _block(a, b, c, d, e, f, g, h, padded, i)
        i = add(i, 64)
    }
}
