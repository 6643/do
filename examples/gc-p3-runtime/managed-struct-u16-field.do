Box {
    values [u16]
    tag i32
}

replace(box Box, values [u16]) -> Box {
    return @set(box, .values, values)
}

start() {}
