Box {
    value [u8]
    tag i32
}

#T
update(box T, next [u8]) -> T {
    return @set(box, .value, next)
}

relay(box Box, next [u8]) -> Box {
    return update(box, next)
}

start() {}
