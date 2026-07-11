LoadError error = Bad

Point {
    x usize
    y usize
}

make(data [u8]) -> Point | LoadError {
    n usize = @len(data)
    point Point = Point{x = n, y = n}
    return point
}

start() {
    data [u8] = "abc"
    result Point | LoadError = make(data)
    size usize = @len(data)
    if @eq(size, 3) return
    if @is(result, LoadError) return
    if @is(result, Point) return
    return
}
