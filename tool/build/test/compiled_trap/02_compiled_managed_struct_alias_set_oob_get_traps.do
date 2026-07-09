Box {
    value [u8]
}

test "compiled managed struct alias set oob get traps" {
    bytes [u8] = "abc"
    next [u8] = "def"
    box Box = Box{value = bytes}
    alias Box = box
    box = @set(box, .value, next)
    alias_value [u8] = @get(alias, .value)
    bad u8 = @get(alias_value, 3)
    _ = bad
    return
}
