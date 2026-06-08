Box {
    value [u8]
}

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    xs [Box] = .{box}
    out Box = @get(xs, 0)
    value [u8] = @get(out, .value)
    return
}
