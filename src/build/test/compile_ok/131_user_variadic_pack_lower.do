count(rest ...i32) -> usize {
    return @len(rest)
}

start() {
    n usize = count(1, 2, 3)
    return
}
