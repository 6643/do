Box {
    value [u8]
    tag i32
}

test "compiled managed struct alias set preserves other field" {
    value [u8] = "abc"
    tag i32 = 7
    next [u8] = "def"
    box Box = Box{value = value, tag = tag}
    alias Box = box
    box = @set(box, .value, next)

    alias_value [u8] = @get(alias, .value)
    alias_tag i32 = @get(alias, .tag)
    box_value [u8] = @get(box, .value)
    box_tag i32 = @get(box, .tag)

    ok bool = true
    ok = @and(ok, @eq(alias_value, "abc"))
    ok = @and(ok, @eq(alias_tag, 7))
    ok = @and(ok, @eq(box_value, "def"))
    ok = @and(ok, @eq(box_tag, 7))
    if ok return
}
