start() {
    data [u8] = "abcdefgh"
    a u8 = @load_u8(data, 0)
    b u16 = @load_u16_le(data, 1)
    c u32 = @load_u32_le(data, 2)
    d u64 = @load_u64_le(data, 0)
    return
}
