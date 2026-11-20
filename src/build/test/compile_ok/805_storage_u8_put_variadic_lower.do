start() {
    data [u8] = "a"
    data = @put(data, 98, 99)
    first u8 = @get(data, 1)
    last u8 = @get(data, 2)
    return
}
