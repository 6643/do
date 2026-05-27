Text = @/text.do/Text
List = @/list.do/List
list_empty = @/list.do/empty
list_put = @/list.do/put
list_len = @/list.do/len
list_items = @/list.do/items
read_u32_le = @/binary.do/read_u32_le

_md5_a0 u32 = 1732584193
_md5_b0 u32 = 4023233417
_md5_c0 u32 = 2562383102
_md5_d0 u32 = 271733878

md5_f(x u32, y u32, z u32) -> u32 {
    return bit_or_u32(bit_and_u32(x, y), bit_and_u32(bit_not_u32(x), z))
}

md5_g(x u32, y u32, z u32) -> u32 {
    return bit_or_u32(bit_and_u32(x, z), bit_and_u32(y, bit_not_u32(z)))
}

md5_h(x u32, y u32, z u32) -> u32 {
    return bit_xor_u32(bit_xor_u32(x, y), z)
}

md5_i(x u32, y u32, z u32) -> u32 {
    return bit_xor_u32(y, bit_or_u32(x, bit_not_u32(z)))
}

_append_u32_le(out List<u8>, value u32) -> List<u8> {
    out = list_put(out, to_u8(rem(value, 256)))
    out = list_put(out, to_u8(rem(div(value, 256), 256)))
    out = list_put(out, to_u8(rem(div(value, 65536), 256)))
    out = list_put(out, to_u8(rem(div(value, 16777216), 256)))
    return out
}

_append_u64_le(out List<u8>, value u64) -> List<u8> {
    out = list_put(out, to_u8(rem(value, 256)))
    out = list_put(out, to_u8(rem(div(value, 256), 256)))
    out = list_put(out, to_u8(rem(div(value, 65536), 256)))
    out = list_put(out, to_u8(rem(div(value, 16777216), 256)))
    out = list_put(out, to_u8(rem(div(value, 4294967296), 256)))
    out = list_put(out, to_u8(rem(div(value, 1099511627776), 256)))
    out = list_put(out, to_u8(rem(div(value, 281474976710656), 256)))
    out = list_put(out, to_u8(rem(div(value, 72057594037927936), 256)))
    return out
}

_pad(data Text) -> List<u8> {
    out List<u8> = list_empty()
    loop b, _ = data {
        out = list_put(out, b)
    }
    out = list_put(out, 128)
    loop {
        if eq(rem(list_len(out), 64), 56) return _append_u64_le(out, mul(to_u64(len(data)), 8))
        out = list_put(out, 0)
    }
}

_block(a u32, b u32, c u32, d u32, block List<u8>, base usize) -> u32, u32, u32, u32 {
    items [u8] = list_items(block)
    x0 u32 = read_u32_le(items, base)
    x1 u32 = read_u32_le(items, add(base, 4))
    x2 u32 = read_u32_le(items, add(base, 8))
    x3 u32 = read_u32_le(items, add(base, 12))
    x4 u32 = read_u32_le(items, add(base, 16))
    x5 u32 = read_u32_le(items, add(base, 20))
    x6 u32 = read_u32_le(items, add(base, 24))
    x7 u32 = read_u32_le(items, add(base, 28))
    x8 u32 = read_u32_le(items, add(base, 32))
    x9 u32 = read_u32_le(items, add(base, 36))
    xa u32 = read_u32_le(items, add(base, 40))
    xb u32 = read_u32_le(items, add(base, 44))
    xc u32 = read_u32_le(items, add(base, 48))
    xd u32 = read_u32_le(items, add(base, 52))
    xe u32 = read_u32_le(items, add(base, 56))
    xf u32 = read_u32_le(items, add(base, 60))

    aa u32 = a
    bb u32 = b
    cc u32 = c
    dd u32 = d

    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(bb, cc, dd), aa), x0), 3614090360), 7))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(aa, bb, cc), dd), x1), 3905402710), 12))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(dd, aa, bb), cc), x2), 606105819), 17))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(cc, dd, aa), bb), x3), 3250441966), 22))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(bb, cc, dd), aa), x4), 4118548399), 7))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(aa, bb, cc), dd), x5), 1200080426), 12))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(dd, aa, bb), cc), x6), 2821735955), 17))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(cc, dd, aa), bb), x7), 4249261313), 22))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(bb, cc, dd), aa), x8), 1770035416), 7))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(aa, bb, cc), dd), x9), 2336552879), 12))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(dd, aa, bb), cc), xa), 4294925233), 17))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(cc, dd, aa), bb), xb), 2304563134), 22))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(bb, cc, dd), aa), xc), 1804603682), 7))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(aa, bb, cc), dd), xd), 4254626195), 12))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(dd, aa, bb), cc), xe), 2792965006), 17))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_f(cc, dd, aa), bb), xf), 1236535329), 22))

    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(bb, cc, dd), aa), x1), 4129170786), 5))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(aa, bb, cc), dd), x6), 3225465664), 9))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(dd, aa, bb), cc), xb), 643717713), 14))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(cc, dd, aa), bb), x0), 3921069994), 20))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(bb, cc, dd), aa), x5), 3593408605), 5))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(aa, bb, cc), dd), xa), 38016083), 9))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(dd, aa, bb), cc), xf), 3634488961), 14))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(cc, dd, aa), bb), x4), 3889429448), 20))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(bb, cc, dd), aa), x9), 568446438), 5))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(aa, bb, cc), dd), xe), 3275163606), 9))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(dd, aa, bb), cc), x3), 4107603335), 14))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(cc, dd, aa), bb), x8), 1163531501), 20))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(bb, cc, dd), aa), xd), 2850285829), 5))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(aa, bb, cc), dd), x2), 4243563512), 9))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(dd, aa, bb), cc), x7), 1735328473), 14))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_g(cc, dd, aa), bb), xc), 2368359562), 20))

    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(bb, cc, dd), aa), x5), 4294588738), 4))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(aa, bb, cc), dd), x8), 2272392833), 11))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(dd, aa, bb), cc), xb), 1839030562), 16))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(cc, dd, aa), bb), xe), 4259657740), 23))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(bb, cc, dd), aa), x1), 2763975236), 4))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(aa, bb, cc), dd), x4), 1272893353), 11))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(dd, aa, bb), cc), x7), 4139469664), 16))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(cc, dd, aa), bb), xa), 3200236656), 23))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(bb, cc, dd), aa), xd), 681279174), 4))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(aa, bb, cc), dd), x0), 3936430074), 11))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(dd, aa, bb), cc), x3), 3572445317), 16))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(cc, dd, aa), bb), x6), 76029189), 23))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(bb, cc, dd), aa), x9), 3654602809), 4))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(aa, bb, cc), dd), xc), 3873151461), 11))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(dd, aa, bb), cc), xf), 530742520), 16))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_h(cc, dd, aa), bb), x2), 3299628645), 23))

    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(bb, cc, dd), aa), x0), 4096336452), 6))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(aa, bb, cc), dd), x7), 1126891415), 10))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(dd, aa, bb), cc), xe), 2878612391), 15))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(cc, dd, aa), bb), x5), 4237533241), 21))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(bb, cc, dd), aa), xc), 1700485571), 6))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(aa, bb, cc), dd), x3), 2399980690), 10))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(dd, aa, bb), cc), xa), 4293915773), 15))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(cc, dd, aa), bb), x1), 2240044497), 21))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(bb, cc, dd), aa), x8), 1873313359), 6))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(aa, bb, cc), dd), xf), 4264355552), 10))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(dd, aa, bb), cc), x6), 2734768916), 15))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(cc, dd, aa), bb), xd), 1309151649), 21))
    aa = add_wrap_u32(bb, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(bb, cc, dd), aa), x4), 4149444226), 6))
    dd = add_wrap_u32(aa, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(aa, bb, cc), dd), xb), 3174756917), 10))
    cc = add_wrap_u32(dd, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(dd, aa, bb), cc), x2), 718787259), 15))
    bb = add_wrap_u32(cc, rotl_u32(add_wrap_u32(add_wrap_u32(add_wrap_u32(md5_i(cc, dd, aa), bb), x9), 3951481745), 21))

    return add_wrap_u32(a, aa), add_wrap_u32(b, bb), add_wrap_u32(c, cc), add_wrap_u32(d, dd)
}

sum(text Text) -> Text {
    padded List<u8> = _pad(text)
    a u32 = _md5_a0
    b u32 = _md5_b0
    c u32 = _md5_c0
    d u32 = _md5_d0

    i usize = 0
    loop {
        if ge(i, list_len(padded)) {
            out List<u8> = list_empty()
            out = _append_u32_le(out, a)
            out = _append_u32_le(out, b)
            out = _append_u32_le(out, c)
            out = _append_u32_le(out, d)
            return get(out, .items)
        }
        a, b, c, d = _block(a, b, c, d, padded, i)
        i = add(i, 64)
    }
}
