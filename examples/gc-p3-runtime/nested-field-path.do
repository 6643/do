Inner {
    tag i32
    value [u8]
}

Outer {
    inner Inner
    id i32
}

update(outer Outer) -> Outer {
    return @set(outer, .inner, .tag, 9)
}

start() {}
