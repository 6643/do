Point {
    x i32
    y i32
}

test "tuple storage pure-scalar struct nested slot" {
    items [Tuple<Point, u8>] = .{}
    p Point = Point{x = 1, y = 2}
    pair Tuple<Point, u8> = Tuple<Point, u8>{p, 7}
    items = @put(items, pair)
    got Tuple<Point, u8> = @get(items, 0)
    a Point = @get(got, 0)
    b u8 = @get(got, 1)
    ok bool = true
    ok = @and(ok, @eq(@get(a, .x), 1))
    ok = @and(ok, @eq(@get(a, .y), 2))
    ok = @and(ok, @eq(b, 7))
    // Nested path: direct Tuple slots, never flattened type.
    a2 Point = @get(items, 0, 0)
    b2 u8 = @get(items, 0, 1)
    ok = @and(ok, @eq(@get(a2, .x), 1))
    ok = @and(ok, @eq(@get(a2, .y), 2))
    ok = @and(ok, @eq(b2, 7))
    if ok return
}
