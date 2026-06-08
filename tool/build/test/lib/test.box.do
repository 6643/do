Box {
    value [u8]
}

make_box() -> Box {
    bytes [u8] = "box"
    box Box = Box{value = bytes}
    return box
}
