Leaf {
    value [u8]
    tag i32
}

Inner {
    leaf Leaf
    tag i32
}

Outer {
    inner Inner
    tag i32
}

update(outer Outer) -> Outer {
    return @set(outer, .inner, .leaf, .tag, 9)
}

start() {}
