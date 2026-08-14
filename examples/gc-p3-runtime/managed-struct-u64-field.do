Box {
    values [u64]
    tag i32
}

replace(box Box, values [u64]) -> Box {
    return @set(box, .values, values)
}

start() {}
