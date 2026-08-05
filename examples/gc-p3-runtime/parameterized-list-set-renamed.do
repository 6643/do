replace(bytes [u8], offset usize, next u8) -> [u8] {
    return @set(bytes, offset, next)
}

start() {}
