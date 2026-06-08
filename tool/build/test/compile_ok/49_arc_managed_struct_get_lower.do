Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    out [u8] = @get(box, .value)
    return
}
