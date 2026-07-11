Point {
    x i32
    y i32
}

size_point(x [u8]) -> Point {
    n i32 = @len(x)
    p Point = Point{x = n, y = n}
    return p
}

start() {
    data [u8] = "abc"
    p Point = size_point(data)
    return
}
