pair_take(x [u8]) -> [u8], i32 {
    return x, 3
}

pass(data [u8]) -> [u8], i32 {
    return pair_take(data)
}

start() {
    out [u8] = .{}
    n i32 = 0
    out, n = pass("abc")
    return
}
