pair_take(x [u8]) -> [u8], i32 {
    return x, 3
}

start() {
    data [u8] = "abc"
    out [u8] = .{}
    n i32 = 0
    out, n = pair_take(data)
    return
}
