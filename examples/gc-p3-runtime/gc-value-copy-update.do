Box {
    value u32
    tag u32
}

update(box Box) -> Box {
    return @set(box, .value, 123)
}

start() {}
