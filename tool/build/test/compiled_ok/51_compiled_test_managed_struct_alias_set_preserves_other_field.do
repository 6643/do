Box {
    value [u8]
    tag [u8]
}

test "compiled managed struct alias set preserves other field" {
    value [u8] = "abc"
    tag [u8] = "tag"
    next [u8] = "def"
    box Box = Box{value = value, tag = tag}
    alias Box = box
    box = @set(box, .value, next)

    alias_value [u8] = @get(alias, .value)
    alias_tag [u8] = @get(alias, .tag)
    box_value [u8] = @get(box, .value)
    box_tag [u8] = @get(box, .tag)

    ok bool = true
    ok = @and(ok, @eq(alias_value, "abc"))
    ok = @and(ok, @eq(alias_tag, "tag"))
    ok = @and(ok, @eq(box_value, "def"))
    ok = @and(ok, @eq(box_tag, "tag"))
    if ok return
}
