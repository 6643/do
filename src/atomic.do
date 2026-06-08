mem_read_u32_le = @lib("mem.do", mem_read_u32_le)
mem_write_u32_le = @lib("mem.do", mem_write_u32_le)
add_wrap_u32 = @lib("math.do", add_wrap_u32)

.sub_wrap_u32(a u32, b u32) -> u32 {
    if @ge(a, b) return @sub(a, b)
    return @to_u32(@sub(@add(@to_u64(a), 4294967296), @to_u64(b)))
}

atomic_load_u32(data [u8], offset usize) -> u32 {
    return mem_read_u32_le(data, offset)
}

atomic_store_u32(data [u8], offset usize, value u32) -> [u8] {
    return mem_write_u32_le(data, offset, value)
}

atomic_exchange_u32(data [u8], offset usize, value u32) -> [u8], u32 {
    old u32 = atomic_load_u32(data, offset)
    return atomic_store_u32(data, offset, value), old
}

atomic_compare_exchange_u32(data [u8], offset usize, expected u32, value u32) -> [u8], u32, bool {
    old u32 = atomic_load_u32(data, offset)
    if @ne(old, expected) return data, old, false
    return atomic_store_u32(data, offset, value), old, true
}

atomic_fetch_add_u32(data [u8], offset usize, value u32) -> [u8], u32 {
    old u32 = atomic_load_u32(data, offset)
    next u32 = add_wrap_u32(old, value)
    return atomic_store_u32(data, offset, next), old
}

atomic_fetch_sub_u32(data [u8], offset usize, value u32) -> [u8], u32 {
    old u32 = atomic_load_u32(data, offset)
    next u32 = sub_wrap_u32(old, value)
    return atomic_store_u32(data, offset, next), old
}

atomic_fetch_or_u32(data [u8], offset usize, value u32) -> [u8], u32 {
    old u32 = atomic_load_u32(data, offset)
    next u32 = @or(old, value)
    return atomic_store_u32(data, offset, next), old
}

atomic_fetch_and_u32(data [u8], offset usize, value u32) -> [u8], u32 {
    old u32 = atomic_load_u32(data, offset)
    next u32 = @and(old, value)
    return atomic_store_u32(data, offset, next), old
}

atomic_fetch_xor_u32(data [u8], offset usize, value u32) -> [u8], u32 {
    old u32 = atomic_load_u32(data, offset)
    next u32 = @xor(old, value)
    return atomic_store_u32(data, offset, next), old
}
