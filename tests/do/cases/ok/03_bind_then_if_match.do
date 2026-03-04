pair(a i32, b i32) i32, i32 {
    return a, b
}

test "bind then if match" {
    x, y = pair(1, 2)
    if x {
        match y {
            _ => return,
        }
    }
}
