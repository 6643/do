#T
Box {
    value T
}

accept(x Box<i32 | nil>) {
    return
}

test "type arg inline union" {
    x = Box<i32 | nil>{value = 1}
    accept(x)
    return
}
