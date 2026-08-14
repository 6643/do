Box {
    flags [bool]
    tag i32
}

replace(box Box, flags [bool]) -> Box {
    return @set(box, .flags, flags)
}

start() {}
