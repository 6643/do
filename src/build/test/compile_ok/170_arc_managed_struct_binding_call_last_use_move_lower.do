Box {
    value [u8]
}

move_box(box Box) -> Box {
    return box
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    out Box = move_box(box)
    return
}
