Box {
    value [u8]
}

nop() -> nil {
    return nil
}

move_box(box Box) -> Box {
    return box
}

pass(box Box) -> Box {
    defer nop()
    return move_box(box)
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    out Box = pass(box)
    return
}
