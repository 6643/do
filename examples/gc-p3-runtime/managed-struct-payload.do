Box {
    value [u8]
    tag i32
}

update(box Box, value [u8]) -> Box {
    return @set(box, .value, value)
}

start() {}
