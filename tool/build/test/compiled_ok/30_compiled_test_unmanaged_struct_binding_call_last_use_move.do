Point {
    x i32
    y i32
}

size_point(x [u8]) -> Point {
    n i32 = @len(x)
    p Point = Point{x = n, y = n}
    return p
}

test "compiled unmanaged struct binding call last use move" {
    data [u8] = .{1, 2, 3, 4}
    p Point = size_point(data)
    if @and(@eq(@get(p, .x), 4), @eq(@get(p, .y), 4)) return
}
