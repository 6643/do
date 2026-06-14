take(x [u8]) -> i32 {
    return @len(x)
}

start() {
    data [u8] = "abc"
    n i32 = 0
    n = take(data)
    return
}
