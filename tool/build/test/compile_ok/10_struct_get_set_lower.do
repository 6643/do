Point {
    x i32
    y i32
}

start() {
    p Point = Point{x = 1, y = 2}
    p = @set(p, .x, 7)
    x i32 = @get(p, .x)
    return
}
