Point {
    x i32
    y i32
}

make_point() -> Point {
    p Point = Point{x = 1, y = 2}
    return p
}

start() {
    p Point = make_point()
    x i32 = @get(p, .x)
    y i32 = @get(p, .y)
    return
}
