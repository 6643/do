make_partial() -> [u8], i32 {
    keep [u8] = "keep"
    drop [u8] = "drop"
    return keep, 7
}

start() {
    data [u8] = "data"
    count i32 = 0
    data, count = make_partial()
    return
}
