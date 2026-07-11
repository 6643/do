Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    alias Box = box
    return
}
