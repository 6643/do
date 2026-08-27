Core {
    value [u8]
    tag i32
}

Leaf {
    core Core
    tag i32
}

Middle {
    leaf Leaf
    tag i32
}

Inner {
    middle Middle
    tag i32
}

Outer {
    inner Inner
    tag i32
}

update(outer Outer) -> Outer {
    return @set(outer, .inner, .middle, .leaf, .core, .tag, 13)
}

start() {}
