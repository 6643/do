make_values() -> [i8] {
    return .{7, 12, 17}
}

update(input [i8]) -> [i8] {
    return @set(input, 1, 65)
}

start() {}
