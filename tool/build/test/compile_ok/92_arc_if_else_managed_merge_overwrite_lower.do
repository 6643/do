start() {
    x [u8] = "x"
    if @eq(@len(x), 1) {
        y [u8] = "y"
        x = y
    } else {
        z [u8] = "z"
        x = z
    }
    out [u8] = x
    return
}
