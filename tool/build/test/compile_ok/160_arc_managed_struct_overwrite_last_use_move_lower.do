Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    next_text [u8] = "def"
    box Box = Box{value = bytes}
    next_box Box = Box{value = next_text}
    box = next_box
    return
}
