List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_add = @lib("list.do", list_add)
list_len = @lib("list.do", list_len)
list_items = @lib("list.do", items)
read_u32_le = @lib("binary.do", read_u32_le)

_md5_a0 u32 = 1732584193
_md5_b0 u32 = 4023233417
_md5_c0 u32 = 2562383102
_md5_d0 u32 = 271733878

md5_f(x u32, y u32, z u32) -> u32 {
    return @or(@and(x, y), @and(bit_not_u32(x), z))
}

md5_g(x u32, y u32, z u32) -> u32 {
    return @or(@and(x, z), @and(y, bit_not_u32(z)))
}

md5_h(x u32, y u32, z u32) -> u32 {
    return @xor(@xor(x, y), z)
}

md5_i(x u32, y u32, z u32) -> u32 {
    return @xor(y, @or(x, bit_not_u32(z)))
}

_md5_s [u32] = .{
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
}

_md5_k [u32] = .{
    3614090360, 3905402710, 606105819, 3250441966, 4118548399, 1200080426, 2821735955, 4249261313,
    1770035416, 2336552879, 4294925233, 2304563134, 1804603682, 4254626195, 2792965006, 1236535329,
    4129170786, 3225465664, 643717713, 3921069994, 3593408605, 38016083, 3634488961, 3889429448,
    568446438, 3275163606, 4107603335, 1163531501, 2850285829, 4243563512, 1735328473, 2368359562,
    4294588738, 2272392833, 1839030562, 4259657740, 2763975236, 1272893353, 4139469664, 3200236656,
    681279174, 3936430074, 3572445317, 76029189, 3654602809, 3873151461, 530742520, 3299628645,
    4096336452, 1126891415, 2878612391, 4237533241, 1700485571, 2399980690, 4293915773, 2240044497,
    1873313359, 4264355552, 2734768916, 1309151649, 4149444226, 3174756917, 718787259, 3951481745,
}

.round_mix(i usize, b u32, c u32, d u32) -> u32 {
    if @lt(i, 16) return md5_f(b, c, d)
    if @lt(i, 32) return md5_g(b, c, d)
    if @lt(i, 48) return md5_h(b, c, d)
    return md5_i(b, c, d)
}

.word_index(i usize) -> usize {
    if @lt(i, 16) return i
    if @lt(i, 32) return @rem(@add(@mul(5, i), 1), 16)
    if @lt(i, 48) return @rem(@add(@mul(3, i), 5), 16)
    return @rem(@mul(7, i), 16)
}

.step(a u32, b u32, mix u32, word u32, k u32, s u32) -> u32 {
    return add_wrap_u32(b, @rotl(add_wrap_u32(add_wrap_u32(add_wrap_u32(mix, a), word), k), s))
}

.append_u32_le(out List<u8>, value u32) -> List<u8> {
    return list_add(out, @as(u8, @rem(value, 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 16777216), 256)))
}

.append_u64_le(out List<u8>, value u64) -> List<u8> {
    return list_add(out, @as(u8, @rem(value, 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 16777216), 256)), @as(u8, @rem(@div(value, 4294967296), 256)), @as(u8, @rem(@div(value, 1099511627776), 256)), @as(u8, @rem(@div(value, 281474976710656), 256)), @as(u8, @rem(@div(value, 72057594037927936), 256)))
}

.pad(data [u8]) -> List<u8> {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    loop byte, _ = data {
        out = list_add(out, byte)
    }
    out = list_add(out, 128)
    loop {
        if @eq(@rem(list_len(out), 64), 56) return append_u64_le(out, @mul(@as(u64, @len(data)), 8))
        out = list_add(out, 0)
    }
}

.block(a u32, b u32, c u32, d u32, block List<u8>, base usize) -> u32, u32, u32, u32 {
    items [u8] = list_items(block)
    words [u32] = @put(.{}, read_u32_le(items, base), read_u32_le(items, @add(base, 4)), read_u32_le(items, @add(base, 8)), read_u32_le(items, @add(base, 12)), read_u32_le(items, @add(base, 16)), read_u32_le(items, @add(base, 20)), read_u32_le(items, @add(base, 24)), read_u32_le(items, @add(base, 28)), read_u32_le(items, @add(base, 32)), read_u32_le(items, @add(base, 36)), read_u32_le(items, @add(base, 40)), read_u32_le(items, @add(base, 44)), read_u32_le(items, @add(base, 48)), read_u32_le(items, @add(base, 52)), read_u32_le(items, @add(base, 56)), read_u32_le(items, @add(base, 60)))

    aa u32 = a
    bb u32 = b
    cc u32 = c
    dd u32 = d

    i usize = 0
    loop {
        if @eq(i, 64) return add_wrap_u32(a, aa), add_wrap_u32(b, bb), add_wrap_u32(c, cc), add_wrap_u32(d, dd)

        index usize = word_index(i)
        mix u32 = round_mix(i, bb, cc, dd)
        next u32 = step(aa, bb, mix, @get(words, index), @get(_md5_k, i), @get(_md5_s, i))

        aa = dd
        dd = cc
        cc = bb
        bb = next
        i = @add(i, 1)
    }
}

sum(bytes [u8]) -> [u8] {
    padded List<u8> = pad(bytes)
    a u32 = _md5_a0
    b u32 = _md5_b0
    c u32 = _md5_c0
    d u32 = _md5_d0

    i usize = 0
    loop {
        if @ge(i, list_len(padded)) {
            seed u8 = 0
            out List<u8> = empty_list(seed)
            out = append_u32_le(out, a)
            out = append_u32_le(out, b)
            out = append_u32_le(out, c)
            out = append_u32_le(out, d)
            return list_items(out)
        }
        a, b, c, d = block(a, b, c, d, padded, i)
        i = @add(i, 64)
    }
}
