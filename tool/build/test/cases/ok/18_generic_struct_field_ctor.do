#T
Box {
    value T
}

test "generic struct field ctor" {
    x = Box<i32>{value = 1}
    return
}
