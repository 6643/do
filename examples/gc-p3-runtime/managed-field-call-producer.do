Box {
    value [u8]
    tag i32
}

make() -> [u8] {
    return .{1, 2}
}

replace(box Box) -> Box {
    return @set(box, .value, make())
}

start() {}
