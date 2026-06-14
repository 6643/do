Box {
    value [u8]
}

test "compiled struct get assignment fresh local move" {
    data [u8] = ""
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    data = @get(box, .value)
    if @eq(data, "abc") return
}
