make(x [u8]) -> [u8] {
    return x
}

start() {
    data [u8] = "abc"
    out [u8] = make(data)
    return
}
