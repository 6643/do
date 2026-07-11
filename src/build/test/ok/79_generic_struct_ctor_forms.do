#T
Box {
    value T
}

test "generic struct ctor forms" {
    b1 = Box<i32>{value = 1}
    b2 Box<i32> = Box<i32>{value = 1}
    b3 Box<i32> = .{value = 1}
    return
}
