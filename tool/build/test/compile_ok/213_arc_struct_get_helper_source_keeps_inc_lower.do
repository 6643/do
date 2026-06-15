Box {
    value [u8]
}

make_box() -> Box {
    bytes [u8] = "abc"
    return Box{value = bytes}
}

start() {
    box Box = make_box()
    value [u8] = @get(box, .value)
    return
}
