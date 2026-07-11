Box {
    value [u8]
}

test "compiled struct get binding fresh local move" {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    value [u8] = @get(box, .value)
    if @eq(value, "abc") return
}
