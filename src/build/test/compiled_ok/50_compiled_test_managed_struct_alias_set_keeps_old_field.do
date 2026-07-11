Box {
    value [u8]
}

test "compiled managed struct alias set keeps old field" {
    bytes [u8] = "abc"
    next [u8] = "def"
    box Box = Box{value = bytes}
    alias Box = box
    box = @set(box, .value, next)

    alias_value [u8] = @get(alias, .value)
    box_value [u8] = @get(box, .value)

    ok bool = true
    ok = @and(ok, @eq(alias_value, "abc"))
    ok = @and(ok, @eq(box_value, "def"))
    if ok return
}
