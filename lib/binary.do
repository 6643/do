read_u32_le(bytes [u8], offset usize) -> u32 {
    b0 u32 = to_u32(at(bytes, offset))
    b1 u32 = to_u32(at(bytes, add(offset, 1)))
    b2 u32 = to_u32(at(bytes, add(offset, 2)))
    b3 u32 = to_u32(at(bytes, add(offset, 3)))
    return add(add(add(b0, mul(b1, 256)), mul(b2, 65536)), mul(b3, 16777216))
}

read_u32_be(bytes [u8], offset usize) -> u32 {
    b0 u32 = to_u32(at(bytes, offset))
    b1 u32 = to_u32(at(bytes, add(offset, 1)))
    b2 u32 = to_u32(at(bytes, add(offset, 2)))
    b3 u32 = to_u32(at(bytes, add(offset, 3)))
    return add(add(add(mul(b0, 16777216), mul(b1, 65536)), mul(b2, 256)), b3)
}
