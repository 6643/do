// Struct and Union Test
malloc(size i32) -> i32 { 0 }

Point {
    x i32,
    y i32,
}

Shape = .circle(i32) | .rect(Point) | .none

test_struct() {
    p = Point { x: 10, y: 20 };
    vx = p.x;
    vy = p.y;
    
    s = .circle(5);
    
    res = match s {
        .circle(r) => r * 2,
        .rect(p2) => p2.x + p2.y,
        .none => 0
    };
    
    res
}

test_struct();