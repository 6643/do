Point {
    x i32
    y i32
}

test "inferred struct ctor" {
    p Point = .{x = 1, y = 2}
    return
}
