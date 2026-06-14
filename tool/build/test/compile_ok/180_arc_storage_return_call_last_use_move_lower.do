make(x [u8]) -> [u8] {
    return x
}

pass(data [u8]) -> [u8] {
    return make(data)
}

start() {
    out [u8] = pass("abc")
    return
}
