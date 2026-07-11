Point {
    x i32
    y i32
}

start() {
    items [Tuple<Point, u8>] = .{}
    p Point = Point{x = 1, y = 2}
    pair Tuple<Point, u8> = Tuple<Point, u8>{p, 7}
    items = @put(items, pair)
    got Tuple<Point, u8> = @get(items, 0)
    a Point = @get(got, 0)
    b u8 = @get(got, 1)
    _ = a
    _ = b
}
