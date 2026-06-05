#T
Box {
    value T | nil
}

test "generic optional field nil" {
    x = Box<i32>{value = nil}
    return
}
