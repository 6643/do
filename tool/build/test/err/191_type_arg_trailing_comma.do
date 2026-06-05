#T
Box {
    value T
}

test "type arg trailing comma" {
    b Box<i32,> = Box<i32,>{value = 1}
    return
}
