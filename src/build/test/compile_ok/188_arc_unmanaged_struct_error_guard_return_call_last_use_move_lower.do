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

pass(data [u8], ok bool) -> Point | LoadError {
    if ok return make(data)
    return Bad
}

start() {
    result = pass("abc", true)
    if @is(result, LoadError) return
    if @is(result, Point) return
    return
}
