nop() -> nil {
    return nil
}

Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    defer nop()
    value [u8] = @get(box, .value)
    return
}
