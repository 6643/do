List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_add = @lib("list.do", list_add)
list_len = @lib("list.do", list_len)
list_items = @lib("list.do", items)
read_u32_be = @lib("binary.do", read_u32_be)
add_wrap_u32 = @lib("math.do", add_wrap_u32)
bit_not_u32 = @lib("math.do", bit_not_u32)

_sha256_h0 u32 = 1779033703
_sha256_h1 u32 = 3144134277
_sha256_h2 u32 = 1013904242
_sha256_h3 u32 = 2773480762
_sha256_h4 u32 = 1359893119
_sha256_h5 u32 = 2600822924
_sha256_h6 u32 = 528734635
_sha256_h7 u32 = 1541459225

sha256_ch(x u32, y u32, z u32) -> u32 {
    return @or(@and(x, y), @and(bit_not_u32(x), z))
}

sha256_maj(x u32, y u32, z u32) -> u32 {
    return @or(@or(@and(x, y), @and(x, z)), @and(y, z))
}

sha256_big_sigma0(x u32) -> u32 {
    return @xor(@xor(@rotr(x, 2), @rotr(x, 13)), @rotr(x, 22))
}

sha256_big_sigma1(x u32) -> u32 {
    return @xor(@xor(@rotr(x, 6), @rotr(x, 11)), @rotr(x, 25))
}

sha256_small_sigma0(x u32) -> u32 {
    return @xor(@xor(@rotr(x, 7), @rotr(x, 18)), @shr(x, 3))
}

sha256_small_sigma1(x u32) -> u32 {
    return @xor(@xor(@rotr(x, 17), @rotr(x, 19)), @shr(x, 10))
}

.append_u64_be(out List<u8>, value u64) -> List<u8> {
    return list_add(out, @as(u8, @rem(@div(value, 72057594037927936), 256)), @as(u8, @rem(@div(value, 281474976710656), 256)), @as(u8, @rem(@div(value, 1099511627776), 256)), @as(u8, @rem(@div(value, 4294967296), 256)), @as(u8, @rem(@div(value, 16777216), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(value, 256)))
}

.append_u32_be(out List<u8>, value u32) -> List<u8> {
    return list_add(out, @as(u8, @rem(@div(value, 16777216), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(value, 256)))
}

.pad(bytes [u8]) -> List<u8> {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    loop byte, _ = bytes {
        out = list_add(out, byte)
    }
    out = list_add(out, 128)
    loop {
        if @eq(@rem(list_len(out), 64), 56) return append_u64_be(out, @mul(@as(u64, @len(bytes)), 8))
        out = list_add(out, 0)
    }
}

.block(h0 u32, h1 u32, h2 u32, h3 u32, h4 u32, h5 u32, h6 u32, h7 u32, chunk List<u8>, base usize) -> u32, u32, u32, u32, u32, u32, u32, u32 {
    items [u8] = list_items(chunk)
    w [u32] = .{read_u32_be(items, base), read_u32_be(items, @add(base, 4)), read_u32_be(items, @add(base, 8)), read_u32_be(items, @add(base, 12)), read_u32_be(items, @add(base, 16)), read_u32_be(items, @add(base, 20)), read_u32_be(items, @add(base, 24)), read_u32_be(items, @add(base, 28)), read_u32_be(items, @add(base, 32)), read_u32_be(items, @add(base, 36)), read_u32_be(items, @add(base, 40)), read_u32_be(items, @add(base, 44)), read_u32_be(items, @add(base, 48)), read_u32_be(items, @add(base, 52)), read_u32_be(items, @add(base, 56)), read_u32_be(items, @add(base, 60))}
    sha256_k [u32] = .{1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298}

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
        if @eq(i, 64) {
            return add_wrap_u32(h0, a), add_wrap_u32(h1, b), add_wrap_u32(h2, c), add_wrap_u32(h3, d), add_wrap_u32(h4, e), add_wrap_u32(h5, f), add_wrap_u32(h6, g), add_wrap_u32(h7, h)
        }

        idx usize = @rem(i, 16)
        if @ge(i, 16) {
            s0 u32 = sha256_small_sigma0(@get(w, @rem(@sub(i, 15), 16)))
            s1 u32 = sha256_small_sigma1(@get(w, @rem(@sub(i, 2), 16)))
            next u32 = add_wrap_u32(add_wrap_u32(add_wrap_u32(s1, @get(w, @rem(@sub(i, 7), 16))), s0), @get(w, idx))
            w = @set(w, idx, next)
        }

        wi u32 = @get(w, idx)
        t1 u32 = add_wrap_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(h, sha256_big_sigma1(e)), sha256_ch(e, f, g)), @get(sha256_k, i)), wi)
        t2 u32 = add_wrap_u32(sha256_big_sigma0(a), sha256_maj(a, b, c))

        h = g
        g = f
        f = e
        e = add_wrap_u32(d, t1)
        d = c
        c = b
        b = a
        a = add_wrap_u32(t1, t2)
        i = @add(i, 1)
    }
}

sum(bytes [u8]) -> [u8] {
    padded List<u8> = pad(bytes)
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
        if @ge(i, list_len(padded)) {
            seed u8 = 0
            out List<u8> = empty_list(seed)
            out = append_u32_be(out, a)
            out = append_u32_be(out, b)
            out = append_u32_be(out, c)
            out = append_u32_be(out, d)
            out = append_u32_be(out, e)
            out = append_u32_be(out, f)
            out = append_u32_be(out, g)
            out = append_u32_be(out, h)
            return list_items(out)
        }
        a, b, c, d, e, f, g, h = block(a, b, c, d, e, f, g, h, padded, i)
        i = @add(i, 64)
    }
}
