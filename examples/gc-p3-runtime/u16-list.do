make_values() -> [u16] {
    return .{7, 12, 17}
}

update(input [u16]) -> [u16] {
    return @set(input, 1, 65)
}

start() {}
