Box {
    values [i32]
    tag i32
}

replace(box Box, values [i32]) -> Box {
    return @set(box, .values, values)
}

start() {}
