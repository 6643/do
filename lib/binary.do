read_u32_le(bytes [u8], offset usize) -> u32 {
    return @load_u32_le(bytes, offset)
}

read_u32_be(bytes [u8], offset usize) -> u32 {
    b0 u32 = @as(u32, @get(bytes, offset))
    b1 u32 = @as(u32, @get(bytes, @add(offset, 1)))
    b2 u32 = @as(u32, @get(bytes, @add(offset, 2)))
    b3 u32 = @as(u32, @get(bytes, @add(offset, 3)))
    return @add(@mul(b0, 16777216), @mul(b1, 65536), @mul(b2, 256), b3)
}

read_u16_le(bytes [u8], offset usize) -> u16 {
    return @load_u16_le(bytes, offset)
}

read_u16_be(bytes [u8], offset usize) -> u16 {
    b0 u16 = @as(u16, @get(bytes, offset))
    b1 u16 = @as(u16, @get(bytes, @add(offset, 1)))
    return @add(@mul(b0, 256), b1)
}

read_u64_le(bytes [u8], offset usize) -> u64 {
    return @load_u64_le(bytes, offset)
}

read_u64_be(bytes [u8], offset usize) -> u64 {
    b0 u64 = @as(u64, @get(bytes, offset))
    b1 u64 = @as(u64, @get(bytes, @add(offset, 1)))
    b2 u64 = @as(u64, @get(bytes, @add(offset, 2)))
    b3 u64 = @as(u64, @get(bytes, @add(offset, 3)))
    b4 u64 = @as(u64, @get(bytes, @add(offset, 4)))
    b5 u64 = @as(u64, @get(bytes, @add(offset, 5)))
    b6 u64 = @as(u64, @get(bytes, @add(offset, 6)))
    b7 u64 = @as(u64, @get(bytes, @add(offset, 7)))
    return @add(@mul(b0, 72057594037927936), @mul(b1, 281474976710656), @mul(b2, 1099511627776), @mul(b3, 4294967296), @mul(b4, 16777216), @mul(b5, 65536), @mul(b6, 256), b7)
}

write_u16_le(value u16) -> [u8] {
    return .{@as(u8, @rem(value, 256)), @as(u8, @div(value, 256))}
}

write_u16_be(value u16) -> [u8] {
    return .{@as(u8, @div(value, 256)), @as(u8, @rem(value, 256))}
}

write_u32_le(value u32) -> [u8] {
    return .{@as(u8, @rem(value, 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 16777216), 256))}
}

write_u32_be(value u32) -> [u8] {
    return .{@as(u8, @rem(@div(value, 16777216), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(value, 256))}
}

write_u64_le(value u64) -> [u8] {
    return .{@as(u8, @rem(value, 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 16777216), 256)), @as(u8, @rem(@div(value, 4294967296), 256)), @as(u8, @rem(@div(value, 1099511627776), 256)), @as(u8, @rem(@div(value, 281474976710656), 256)), @as(u8, @rem(@div(value, 72057594037927936), 256))}
}

write_u64_be(value u64) -> [u8] {
    return .{@as(u8, @rem(@div(value, 72057594037927936), 256)), @as(u8, @rem(@div(value, 281474976710656), 256)), @as(u8, @rem(@div(value, 1099511627776), 256)), @as(u8, @rem(@div(value, 4294967296), 256)), @as(u8, @rem(@div(value, 16777216), 256)), @as(u8, @rem(@div(value, 65536), 256)), @as(u8, @rem(@div(value, 256), 256)), @as(u8, @rem(value, 256))}
}
