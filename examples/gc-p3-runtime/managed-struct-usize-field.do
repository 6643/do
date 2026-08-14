Box {
    values [usize]
    tag i32
}

replace(box Box, values [usize]) -> Box {
    return @set(box, .values, values)
}

start() {}
