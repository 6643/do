Inner {
    value [u8]
}

Outer {
    inner Inner
    tag i32
}

replace(outer Outer, inner Inner) -> Outer {
    return @set(outer, .inner, inner)
}

start() {}
