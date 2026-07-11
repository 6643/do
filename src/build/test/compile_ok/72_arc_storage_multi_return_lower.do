make_pair() -> [u8], [u8] {
    left [u8] = "left"
    right [u8] = "right"
    return left, right
}

start() {
    first [u8] = "first"
    second [u8] = "second"
    first, second = make_pair()
    return
}
