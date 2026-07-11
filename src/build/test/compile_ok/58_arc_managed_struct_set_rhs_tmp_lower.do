Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    other Box = Box{value = bytes}
    box Box = Box{value = bytes}
    box = @set(box, .value, @get(other, .value))
    return
}
