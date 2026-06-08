
hash(bytes [u8]) -> u64 {
    h u64 = 0
    loop b, _ = bytes {
        h = @rem(@add(@mul(h, 131), @to_u64(b)), 1000000007)
    }
    return h
}
