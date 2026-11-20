start() {
    data [u8] = "abcdefgh"
    a u8 = @load_u8(data, 0)
    b i8 = @load_i8(data, 1)
    c u16 = @load_u16_le(data, 1)
    d i16 = @load_i16_le(data, 2)
    e u32 = @load_u32_le(data, 2)
    f i32 = @load_i32_le(data, 3)
    g u64 = @load_u64_le(data, 0)
    h i64 = @load_i64_le(data, 0)
    return
}

read_u16(data [u8], offset usize) -> u16 {
    return @load_u16_le(data, offset)
}
