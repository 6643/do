count(rest ...i32) -> usize {
    return @len(rest)
}

forward(rest ...i32) -> usize {
    return count(...rest)
}

start() {
    n usize = forward(1, 2)
    return
}
