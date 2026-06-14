Box {
    value [u8]
}

nop() {
    return
}

start() {
    bytes [u8] = "abc"
    next [u8] = "def"
    box Box = Box{value = bytes}
    defer nop()
    box = @set(box, .value, next)
    return
}
