start() {
    x [u8] = "x"
    loop {
        a [u8] = "a"
        if @eq(@len(a), 1) {
            b [u8] = "b"
            x = b
            continue
        } else {
            c [u8] = "c"
            x = c
            break
        }
    }
    out [u8] = x
    return
}
