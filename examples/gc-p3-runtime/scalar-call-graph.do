leaf(value u32) -> u32 {
    return @add(value, 1)
}

middle(value u32) -> u32 {
    return leaf(value)
}

caller(value u32) -> u32 {
    return middle(value)
}

start() {}
