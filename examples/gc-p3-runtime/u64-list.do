make_values() -> [u64] {
    return .{7, 12, 17}
}

update(input [u64]) -> [u64] {
    return @set(input, 1, 65)
}

start() {}
