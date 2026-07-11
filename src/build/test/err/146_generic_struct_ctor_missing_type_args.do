#T
Box {
    value T
}

test "generic struct ctor missing type args" {
    b Box<i32> = Box{value = 1}
    return
}
