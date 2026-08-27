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

Top {
    outer Outer
    tag i32
}

update(top Top) -> Top {
    return @set(top, .outer, .inner, .middle, .leaf, .core, .tag, 13)
}

start() {}
