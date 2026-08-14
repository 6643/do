make_values() -> [isize] {
    return .{7, 12, 17}
}

update(input [isize]) -> [isize] {
    return @set(input, 1, 65)
}

start() {}
