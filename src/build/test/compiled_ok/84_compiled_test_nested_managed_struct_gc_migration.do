Inner {
    value [u8]
}

Outer {
    inner Inner
    tag i32
}

test "compiled nested managed struct preserves old value" {
    old [u8] = "abc"
    next [u8] = "def"
    child Inner = Inner{value = old}
    replacement Inner = Inner{value = next}
    box Outer = Outer{inner = child, tag = 7}
    updated Outer = @set(box, .inner, replacement)

    original Inner = @get(box, .inner)
    original_value [u8] = @get(original, .value)
    updated_child Inner = @get(updated, .inner)
    updated_value [u8] = @get(updated_child, .value)
    updated_tag i32 = @get(updated, .tag)

    ok bool = true
    ok = @and(ok, @eq(original_value, "abc"))
    ok = @and(ok, @eq(updated_value, "def"))
    ok = @and(ok, @eq(updated_tag, 7))
    if ok return
}
