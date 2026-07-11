#T
id(x T) -> T {
    return x
}

#U
id(x U) -> U {
    return x
}

test "generic signature alpha duplicate" {
    i i32 = 1
    x = id(i)
    return
}
