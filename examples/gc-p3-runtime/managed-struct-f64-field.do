Box {
    values [f64]
    tag i32
}

replace(box Box, values [f64]) -> Box {
    return @set(box, .values, values)
}

start() {}
