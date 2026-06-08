dup() -> [u8], [u8] {
    data [u8] = "same"
    return data, data
}

start() {
    first [u8] = "first"
    second [u8] = "second"
    first, second = dup()
    return
}
