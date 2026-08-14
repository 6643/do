Box {
    values [i16]
    tag i32
}

replace(box Box, values [i16]) -> Box {
    return @set(box, .values, values)
}

start() {}
