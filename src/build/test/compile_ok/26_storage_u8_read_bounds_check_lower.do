start() {
    data [u8] = "abcdefgh"
    a u8 = @get(data, 1)
    b u64 = @load_u64_le(data, 0)
    return
}
