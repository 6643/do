Box {
    values [i8]
    tag i32
}

replace(box Box, values [i8]) -> Box {
    return @set(box, .values, values)
}

start() {}
