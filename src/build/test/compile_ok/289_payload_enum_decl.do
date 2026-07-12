Message = Quit | Text([u8]) | Binary([u8])

start() {
    m Message = Quit
    _ = m
    return
}
