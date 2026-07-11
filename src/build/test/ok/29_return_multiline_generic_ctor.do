#T
Box {
    value T
}

#T
make(value T) -> Box<T> {
    return Box<T>{value = value}
}

test "return multiline generic ctor" {
    return
}
