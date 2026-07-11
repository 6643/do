Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    alias Box = box
    value [u8] = @get(alias, .value)
    size usize = @len(value)
    return
}
