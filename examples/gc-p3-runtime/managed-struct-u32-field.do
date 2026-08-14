Box {
    values [u32]
    tag i32
}

replace(box Box, values [u32]) -> Box {
    return @set(box, .values, values)
}

start() {}
