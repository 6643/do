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

pass(data [u8]) -> Point | LoadError {
    return make(data)
}

test "compiled unmanaged struct error return call last use move" {
    data [u8] = .{1, 2, 3}
    result = pass(data)
    if @is(result, Point) {
        ok bool = @and(@eq(@get(result, .x), 3), @eq(@get(result, .y), 3))
        if ok return
    }
}
