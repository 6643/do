Box {
    values [f32]
    tag i32
}

replace(box Box, values [f32]) -> Box {
    return @set(box, .values, values)
}

start() {}
