mem_len(data [u8]) -> usize {
    return @len(data)
}

mem_can_access(data [u8], offset usize, count usize) -> bool {
    if @gt(offset, @len(data)) return false
    return @le(count, @sub(@len(data), offset))
}

mem_read_u8(data [u8], offset usize) -> u8 {
    return @load_u8(data, offset)
}

mem_read_u16_le(data [u8], offset usize) -> u16 {
    return @load_u16_le(data, offset)
}

mem_read_u16_be(data [u8], offset usize) -> u16 {
    b0 u16 = @to_u16(@get(data, offset))
    b1 u16 = @to_u16(@get(data, @add(offset, 1)))
    return @add(@mul(b0, 256), b1)
}

mem_read_u32_le(data [u8], offset usize) -> u32 {
    return @load_u32_le(data, offset)
}

mem_read_u32_be(data [u8], offset usize) -> u32 {
    b0 u32 = @to_u32(@get(data, offset))
    b1 u32 = @to_u32(@get(data, @add(offset, 1)))
    b2 u32 = @to_u32(@get(data, @add(offset, 2)))
    b3 u32 = @to_u32(@get(data, @add(offset, 3)))
    return @add(@mul(b0, 16777216), @mul(b1, 65536), @mul(b2, 256), b3)
}

mem_read_u64_le(data [u8], offset usize) -> u64 {
    return @load_u64_le(data, offset)
}

mem_read_u64_be(data [u8], offset usize) -> u64 {
    b0 u64 = @to_u64(@get(data, offset))
    b1 u64 = @to_u64(@get(data, @add(offset, 1)))
    b2 u64 = @to_u64(@get(data, @add(offset, 2)))
    b3 u64 = @to_u64(@get(data, @add(offset, 3)))
    b4 u64 = @to_u64(@get(data, @add(offset, 4)))
    b5 u64 = @to_u64(@get(data, @add(offset, 5)))
    b6 u64 = @to_u64(@get(data, @add(offset, 6)))
    b7 u64 = @to_u64(@get(data, @add(offset, 7)))
    return @add(@mul(b0, 72057594037927936), @mul(b1, 281474976710656), @mul(b2, 1099511627776), @mul(b3, 4294967296), @mul(b4, 16777216), @mul(b5, 65536), @mul(b6, 256), b7)
}

mem_read_bytes(data [u8], offset usize, count usize) -> [u8] {
    out [u8] = .{}
    i usize = 0
    loop {
        if @ge(i, count) return out
        out = @put(out, @get(data, @add(offset, i)))
        i = @add(i, 1)
    }
}

mem_read_bytes_or(data [u8], offset usize, count usize, fallback [u8]) -> [u8], bool {
    if @not(mem_can_access(data, offset, count)) return fallback, false
    return mem_read_bytes(data, offset, count), true
}

mem_write_u8(data [u8], offset usize, value u8) -> [u8] {
    return @set(data, offset, value)
}

mem_write_u16_le(data [u8], offset usize, value u16) -> [u8] {
    out [u8] = data
    out = @set(out, offset, @to_u8(@rem(value, 256)))
    out = @set(out, @add(offset, 1), @to_u8(@div(value, 256)))
    return out
}

mem_write_u16_be(data [u8], offset usize, value u16) -> [u8] {
    out [u8] = data
    out = @set(out, offset, @to_u8(@div(value, 256)))
    out = @set(out, @add(offset, 1), @to_u8(@rem(value, 256)))
    return out
}

mem_write_u32_le(data [u8], offset usize, value u32) -> [u8] {
    out [u8] = data
    out = @set(out, offset, @to_u8(@rem(value, 256)))
    out = @set(out, @add(offset, 1), @to_u8(@rem(@div(value, 256), 256)))
    out = @set(out, @add(offset, 2), @to_u8(@rem(@div(value, 65536), 256)))
    out = @set(out, @add(offset, 3), @to_u8(@rem(@div(value, 16777216), 256)))
    return out
}

mem_write_u32_be(data [u8], offset usize, value u32) -> [u8] {
    out [u8] = data
    out = @set(out, offset, @to_u8(@rem(@div(value, 16777216), 256)))
    out = @set(out, @add(offset, 1), @to_u8(@rem(@div(value, 65536), 256)))
    out = @set(out, @add(offset, 2), @to_u8(@rem(@div(value, 256), 256)))
    out = @set(out, @add(offset, 3), @to_u8(@rem(value, 256)))
    return out
}

mem_write_u64_le(data [u8], offset usize, value u64) -> [u8] {
    out [u8] = data
    out = @set(out, offset, @to_u8(@rem(value, 256)))
    out = @set(out, @add(offset, 1), @to_u8(@rem(@div(value, 256), 256)))
    out = @set(out, @add(offset, 2), @to_u8(@rem(@div(value, 65536), 256)))
    out = @set(out, @add(offset, 3), @to_u8(@rem(@div(value, 16777216), 256)))
    out = @set(out, @add(offset, 4), @to_u8(@rem(@div(value, 4294967296), 256)))
    out = @set(out, @add(offset, 5), @to_u8(@rem(@div(value, 1099511627776), 256)))
    out = @set(out, @add(offset, 6), @to_u8(@rem(@div(value, 281474976710656), 256)))
    out = @set(out, @add(offset, 7), @to_u8(@rem(@div(value, 72057594037927936), 256)))
    return out
}

mem_write_u64_be(data [u8], offset usize, value u64) -> [u8] {
    out [u8] = data
    out = @set(out, offset, @to_u8(@rem(@div(value, 72057594037927936), 256)))
    out = @set(out, @add(offset, 1), @to_u8(@rem(@div(value, 281474976710656), 256)))
    out = @set(out, @add(offset, 2), @to_u8(@rem(@div(value, 1099511627776), 256)))
    out = @set(out, @add(offset, 3), @to_u8(@rem(@div(value, 4294967296), 256)))
    out = @set(out, @add(offset, 4), @to_u8(@rem(@div(value, 16777216), 256)))
    out = @set(out, @add(offset, 5), @to_u8(@rem(@div(value, 65536), 256)))
    out = @set(out, @add(offset, 6), @to_u8(@rem(@div(value, 256), 256)))
    out = @set(out, @add(offset, 7), @to_u8(@rem(value, 256)))
    return out
}

mem_write_bytes(data [u8], offset usize, bytes [u8]) -> [u8] {
    out [u8] = data
    loop byte, index = bytes {
        out = @set(out, @add(offset, index), byte)
    }
    return out
}

mem_write_bytes_or(data [u8], offset usize, bytes [u8]) -> [u8], bool {
    if @not(mem_can_access(data, offset, @len(bytes))) return data, false
    return mem_write_bytes(data, offset, bytes), true
}

mem_fill(data [u8], offset usize, count usize, value u8) -> [u8] {
    out [u8] = data
    i usize = 0
    loop {
        if @ge(i, count) return out
        out = @set(out, @add(offset, i), value)
        i = @add(i, 1)
    }
}

mem_fill_or(data [u8], offset usize, count usize, value u8) -> [u8], bool {
    if @not(mem_can_access(data, offset, count)) return data, false
    return mem_fill(data, offset, count, value), true
}

mem_copy(data [u8], dst usize, src usize, count usize) -> [u8] {
    bytes [u8] = mem_read_bytes(data, src, count)
    return mem_write_bytes(data, dst, bytes)
}

mem_copy_or(data [u8], dst usize, src usize, count usize) -> [u8], bool {
    if @not(mem_can_access(data, src, count)) return data, false
    if @not(mem_can_access(data, dst, count)) return data, false
    return mem_copy(data, dst, src, count), true
}
