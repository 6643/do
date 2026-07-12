Message = Quit | Text([u8]) | Binary([u8])

start() {
    m Message = Quit
    b [u8] = "hi"
    m = Text(b)
    if @is(m, Text) {
        x [u8] = m
        _ = x
    }
    m = Binary(b)
    _ = m
    return
}
