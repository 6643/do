LoadError error = Bad

Point {
    x usize
    y usize
}

nop() -> nil {
    return nil
}

make(data [u8]) -> Point | LoadError {
    n usize = @len(data)
    point Point = Point{x = n, y = n}
    return point
}

pass(data [u8]) -> Point | LoadError {
    defer nop()
    return make(data)
}

start() {
    result = pass("abc")
    if @is(result, LoadError) return
    if @is(result, Point) return
    return
}
