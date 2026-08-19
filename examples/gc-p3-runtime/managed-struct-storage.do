Box {
    value [u8]
    tag i32
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes, tag = 1}
    updated Box = @set(box, .tag, 7)
    value [u8] = @get(updated, .value)
    if @eq(@len(value), 3) return
}
