Box {
    value [u8]
}

move_box(box Box) -> Box {
    return box
}

pass(box Box) -> Box {
    return move_box(box)
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    out Box = pass(box)
    return
}
