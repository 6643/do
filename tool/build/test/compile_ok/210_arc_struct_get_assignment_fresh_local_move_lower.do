Box {
    value [u8]
}

start() {
    data [u8] = ""
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    data = @get(box, .value)
    return
}
