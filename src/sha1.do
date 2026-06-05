List = @list.do/List
empty_list = @list.do/empty_list
list_add = @list.do/list_add
list_len = @list.do/list_len
list_items = @list.do/items
read_u32_be = @binary.do/read_u32_be

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

.sha1_mix(i usize, b u32, c u32, d u32) -> u32 {
    if lt(i, 20) return sha1_f0(b, c, d)
    if lt(i, 40) return sha1_f1(b, c, d)
    if lt(i, 60) return sha1_f2(b, c, d)
    return sha1_f3(b, c, d)
}

.sha1_k(i usize) -> u32 {
    if lt(i, 20) return _sha1_k0
    if lt(i, 40) return _sha1_k1
    if lt(i, 60) return _sha1_k2
    return _sha1_k3
}

.append_u64_be(out List<u8>, value u64) -> List<u8> {
    return list_add(out, to_u8(rem(div(value, 72057594037927936), 256)), to_u8(rem(div(value, 281474976710656), 256)), to_u8(rem(div(value, 1099511627776), 256)), to_u8(rem(div(value, 4294967296), 256)), to_u8(rem(div(value, 16777216), 256)), to_u8(rem(div(value, 65536), 256)), to_u8(rem(div(value, 256), 256)), to_u8(rem(value, 256)))
}

.append_u32_be(out List<u8>, value u32) -> List<u8> {
    return list_add(out, to_u8(rem(div(value, 16777216), 256)), to_u8(rem(div(value, 65536), 256)), to_u8(rem(div(value, 256), 256)), to_u8(rem(value, 256)))
}

.pad(text [u8]) -> List<u8> {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    loop byte, _ = text {
        out = list_add(out, byte)
    }
    out = list_add(out, 128)
    loop {
        if eq(rem(list_len(out), 64), 56) return append_u64_be(out, mul(to_u64(len(text)), 8))
        out = list_add(out, 0)
    }
}

.block(h0 u32, h1 u32, h2 u32, h3 u32, h4 u32, block List<u8>, base usize) -> u32, u32, u32, u32, u32 {
    items [u8] = list_items(block)
    w [u32] = put(.{}, read_u32_be(items, base), read_u32_be(items, add(base, 4)), read_u32_be(items, add(base, 8)), read_u32_be(items, add(base, 12)), read_u32_be(items, add(base, 16)), read_u32_be(items, add(base, 20)), read_u32_be(items, add(base, 24)), read_u32_be(items, add(base, 28)), read_u32_be(items, add(base, 32)), read_u32_be(items, add(base, 36)), read_u32_be(items, add(base, 40)), read_u32_be(items, add(base, 44)), read_u32_be(items, add(base, 48)), read_u32_be(items, add(base, 52)), read_u32_be(items, add(base, 56)), read_u32_be(items, add(base, 60)))

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
            s u32 = bit_xor_u32(bit_xor_u32(get(w, rem(sub(i, 3), 16)), get(w, rem(sub(i, 8), 16))), bit_xor_u32(get(w, rem(sub(i, 14), 16)), get(w, idx)))
            w = set(w, idx, rotl_u32(s, 1))
        }

        wi u32 = get(w, idx)
        f u32 = sha1_mix(i, b, c, d)
        k u32 = sha1_k(i)

        t u32 = add_wrap_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(rotl_u32(a, 5), f), e), wi), k)
        e = d
        d = c
        c = rotl_u32(b, 30)
        b = a
        a = t
        i = add(i, 1)
    }
}

sum(text [u8]) -> [u8] {
    padded List<u8> = pad(text)
    a u32 = _sha1_h0
    b u32 = _sha1_h1
    c u32 = _sha1_h2
    d u32 = _sha1_h3
    e u32 = _sha1_h4

    i usize = 0
    loop {
        if ge(i, list_len(padded)) {
            seed u8 = 0
            out List<u8> = empty_list(seed)
            out = append_u32_be(out, a)
            out = append_u32_be(out, b)
            out = append_u32_be(out, c)
            out = append_u32_be(out, d)
            out = append_u32_be(out, e)
            return list_items(out)
        }
        a, b, c, d, e = block(a, b, c, d, e, padded, i)
        i = add(i, 64)
    }
}
