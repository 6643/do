#T
Box {
    value T
}

accept(x Box<(i32)>) {
    return
}

test "parenthesized type arg" {
    x = Box<i32>{value = 1}
    accept(x)
    return
}
