take(x [u8]) -> i32 {
    return @len(x)
}

start() {
    data [u8] = "abc"
    loop {
        n = take(data)
        again usize = @len(data)
        if @eq(again, 3) break
    }
    return
}
