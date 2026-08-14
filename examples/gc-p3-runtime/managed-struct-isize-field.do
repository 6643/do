Box {
    values [isize]
    tag i32
}

replace(box Box, values [isize]) -> Box {
    return @set(box, .values, values)
}

start() {}
