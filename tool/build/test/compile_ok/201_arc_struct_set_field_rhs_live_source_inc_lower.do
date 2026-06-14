Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    next [u8] = "def"
    box Box = Box{value = bytes}
    box = @set(box, .value, next)
    size usize = @len(next)
    return
}
