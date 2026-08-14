Box {
    values [i64]
    tag i32
}

replace(box Box, values [i64]) -> Box {
    return @set(box, .values, values)
}

start() {}
