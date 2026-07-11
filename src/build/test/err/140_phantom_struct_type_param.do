#T
Marker {
    id i32
}

test "phantom struct type param" {
    a = Marker<i32>{id = 1}
    b = Marker<bool>{id = 1}
    return
}
